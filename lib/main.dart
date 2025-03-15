import 'dart:convert';
import 'dart:io';

import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:fl_caption/common/translate/translate_provider.dart';
import 'package:fl_caption/settings.dart';
import 'package:fl_caption/widgets/error.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/services.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hive_ce_flutter/adapters.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:rhttp/rhttp.dart';
import 'package:window_manager/window_manager.dart';

import 'common/rust/frb_generated.dart';
import 'common/settings_provider.dart';
import 'common/utils/window_util.dart';
import 'common/whisper/provider.dart';

Future<void> main(List<String> args) async {
  if (args.firstOrNull == 'multi_window') {
    return await _handleMultiWindow(args);
  }
  MultiWindowWindowUtil.isMainWindow = true;
  WidgetsFlutterBinding.ensureInitialized();
  await Window.initialize();
  await windowManager.ensureInitialized();
  await windowManager.setAsFrameless();
  await windowManager.setAlwaysOnTop(true);
  await windowManager.setMaximizable(false);
  await Rhttp.init();
  await RustLib.init();
  await Hive.initFlutter();
  runApp(ProviderScope(child: App()));

  doWhenWindowReady(() async {
    appWindow
      ..minSize = Size(640, 80)
      ..size = Size(1320, 180)
      ..alignment = Alignment.bottomCenter
      ..show();
    await Window.setEffect(effect: WindowEffect.transparent, dark: false);
  });
}

Future<void> _handleMultiWindow(List<String> args) async {
  // final windowId = int.parse(args[1]);
  final argument = args[2].isEmpty ? const {} : jsonDecode(args[2]) as Map<String, dynamic>;
  switch (argument["window_type"]) {
    case 'settings':
      await Rhttp.init();
      runApp(ProviderScope(child: SettingsApp()));
      return;
    default:
      throw Exception('Unknown window type');
  }
}

class App extends HookConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caption = ref.watch(dartWhisperCaptionProvider);

    useEffect(() {
      DesktopMultiWindow.setMethodHandler((c, h) => _subWindowMethodHandler(c, h, ref));
      return null;
    }, const []);

    return DragToMoveArea(
      child: FluentApp(
        debugShowCheckedModeBanner: false,
        title: 'Fluent UI',
        theme: FluentThemeData(brightness: Brightness.dark, fontFamily: "SourceHanSansCN-Regular"),
        home: Container(
          color: Colors.black.withValues(alpha: .7),
          child: Stack(
            children: [
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (caption.hasValue) ...[
                      Text(
                        caption.value!.text.isEmpty ? "<wait for Whisper ...>" : caption.value!.text,
                        style: TextStyle(fontSize: 16, color: Colors.white),
                        maxLines: 1,
                      ),
                      SizedBox(height: 12),
                      Consumer(
                        builder: (BuildContext context, WidgetRef ref, Widget? child) {
                          final text = ref.watch(translateProviderProvider);
                          return Text(text, style: TextStyle(fontSize: 22), maxLines: 3);
                        },
                      ),
                    ],
                    if (caption.hasError)
                      HomeErrorWidget(errorType: caption.value?.errorType, errorInfo: caption.error),
                  ],
                ),
              ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        if (caption.hasValue) ...[
                          Text(
                            "audioLang: ${caption.value?.reasoningLang ?? "unknown"}",
                            style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: .6)),
                          ),
                          SizedBox(width: 6),
                          Text(
                            "reasoningSpeed: ${caption.value?.reasoningDuration?.inMilliseconds ?? "?"}ms",
                            style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: .6)),
                          ),
                          SizedBox(width: 6),
                          // auto duration
                          Text(
                            "audioDuration: ${((caption.value?.audioDuration?.inMilliseconds ?? 0) / 1000).toStringAsFixed(2)}s",
                            style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: .6)),
                          ),
                        ],
                      ],
                    ),
                    IconButton(
                      icon: Icon(Icons.logout),
                      onPressed: () async {
                        ref.read(dartWhisperCaptionProvider.notifier).pause();
                        await Future.delayed(const Duration(milliseconds: 100));
                        exit(0);
                      },
                    ),
                  ],
                ),
              ),
              Positioned(
                right: 12,
                top: 12,
                child: Row(children: [IconButton(icon: Icon(FluentIcons.settings), onPressed: _openSettings)]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openSettings() async {
    final windows = await DesktopMultiWindow.getAllSubWindowIds();
    if (windows.isEmpty) {
      final window = await DesktopMultiWindow.createWindow(jsonEncode({'window_type': 'settings'}));
      window.setTitle("Settings");
      await window.center();
      await window.show();
      DesktopMultiWindow.invokeMethod(window.windowId, 'main_window_id_broadcast');
    } else {
      WindowController.fromWindowId(windows.first)
        ..show()
        ..center();
    }
  }

  Future _subWindowMethodHandler(MethodCall call, int fromWindowId, WidgetRef ref) async {
    switch (call.method) {
      case "get_app_settings":
        return (await ref.read(appSettingsProvider.future)).toJson();
      case "set_app_settings":
        final settings = AppSettingsData.fromJson(Map<String, dynamic>.from(call.arguments as Map));
        await ref.read(appSettingsProvider.notifier).setSettings(settings);
        return true;
      case "close_mine_window":
        return await WindowController.fromWindowId(fromWindowId).close();
    }
    return null;
  }
}
