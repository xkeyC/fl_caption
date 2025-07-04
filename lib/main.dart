import 'dart:convert';
import 'dart:io';

import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:fl_caption/common/translate/translate_provider.dart';
import 'package:fl_caption/pages/settings/settings_page.dart';
import 'package:fl_caption/widgets/error.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/services.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hive_ce_flutter/adapters.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rhttp/rhttp.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:window_manager/window_manager.dart';

import 'common/rust/frb_generated.dart';
import 'common/rust/whisper_caption/whisper.dart' show WhisperStatus;
import 'pages/settings/settings_provider.dart';
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

  if (Platform.isMacOS) {
    Window.makeTitlebarTransparent();
    Window.makeWindowFullyTransparent();
    Window.enableFullSizeContentView();
  }

  await Rhttp.init();
  await RustLib.init();
  Hive.init("${(await getApplicationSupportDirectory()).absolute.path}/db");
  runApp(ProviderScope(child: App()));

  doWhenWindowReady(() async {
    appWindow
      ..minSize = Size(640, 80)
      ..size = Size(1320, 120)
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
      debugPrint("_handleMultiWindow -> settings window");
      runApp(ProviderScope(child: SettingsApp()));
      return;
    default:
      throw Exception('Unknown window type');
  }
}

class App extends HookConsumerWidget with WindowListener {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caption = ref.watch(dartWhisperCaptionProvider);

    useEffect(() {
      windowManager.addListener(this);
      windowManager.setPreventClose(true);
      DesktopMultiWindow.setMethodHandler((c, h) => _subWindowMethodHandler(c, h, ref));
      return () async {
        windowManager.removeListener(this);
      };
    }, const []);

    return DragToMoveArea(
      child: FluentApp(
        debugShowCheckedModeBanner: false,
        title: 'Fl Caption',
        theme: FluentThemeData(brightness: Brightness.dark, fontFamily: "SourceHanSansCN-Regular"),
        home: Container(
          color: Colors.black.withValues(alpha: .7),
          child: Column(
            mainAxisSize: MainAxisSize.max,
            children: [
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                    child: Stack(
                      children: [
                        Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (caption.value != null) ...[
                                if (caption.value!.errorType != null ||
                                    caption.value!.errorMessage != null ||
                                    caption.hasError) ...[
                                  HomeErrorWidget(
                                    errorType: caption.value?.errorType,
                                    errorInfo: caption.value!.errorMessage ?? caption.error,
                                  ),
                                ] else ...[
                                  if (caption.value!.whisperStatus == WhisperStatus.loading) ...[
                                    ProgressRing(),
                                  ] else ...[
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 24),
                                      child: Text(
                                        caption.value!.text.isEmpty ? "<wait audio input ...>" : caption.value!.text,
                                        style: TextStyle(fontSize: 16, color: Colors.white),
                                        maxLines: 1,
                                      ),
                                    ),
                                    SizedBox(height: 12),
                                    Consumer(
                                      builder: (BuildContext context, WidgetRef ref, Widget? child) {
                                        final text = ref.watch(translateProviderProvider);
                                        if (text.trim().isEmpty) return SizedBox();
                                        return LayoutBuilder(
                                          builder: (context, constraints) {
                                            final textPainter = TextPainter(
                                              text: TextSpan(text: text, style: TextStyle(fontSize: 22)),
                                              textDirection: TextDirection.ltr,
                                              maxLines: 1,
                                            );
                                            textPainter.layout(maxWidth: constraints.maxWidth);

                                            if (textPainter.didExceedMaxLines) {
                                              int end = text.length;
                                              String truncated = text;

                                              while (end > 0) {
                                                truncated = '...${text.substring(text.length - end)}';
                                                textPainter.text = TextSpan(
                                                  text: truncated,
                                                  style: TextStyle(fontSize: 22),
                                                );
                                                textPainter.layout(maxWidth: constraints.maxWidth);

                                                if (!textPainter.didExceedMaxLines) break;
                                                end--;
                                              }

                                              return Text(truncated, style: TextStyle(fontSize: 22), maxLines: 1);
                                            }

                                            return Text(text, style: TextStyle(fontSize: 22), maxLines: 1);
                                          },
                                        );
                                      },
                                    ),
                                  ],
                                ],
                              ],
                            ],
                          ),
                        ),
                        Positioned(
                          right: 0,
                          top: 3,
                          child: Row(
                            children: [IconButton(icon: Icon(FluentIcons.settings), onPressed: _openSettings)],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(height: 3),
              Padding(
                padding: const EdgeInsets.only(left: 15, right: 8, bottom: 3),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        if (caption.hasValue) ...[
                          if (caption.value?.whisperStatus != null)
                            Text(
                              "whisperStatus: ${caption.value?.whisperStatus.name}",
                              style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: .6)),
                            ),
                          SizedBox(width: 6),
                          Text(
                            "audioLang: ${caption.value?.reasoningLang ?? "unknown"}",
                            style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: .6)),
                          ),
                          SizedBox(width: 6),
                          Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(text: "reasoning "),
                                TextSpan(
                                  text: "${caption.value?.reasoningDuration?.inMilliseconds ?? "?"}ms",
                                  style: TextStyle(
                                    color: _getReasoningColor(
                                      caption.value?.reasoningDuration?.inMilliseconds,
                                      ref.read(appSettingsProvider),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: .6)),
                          ),
                          SizedBox(width: 6),
                          // auto duration
                          Text(
                            "audio: ${((caption.value?.audioDuration?.inMilliseconds ?? 0) / 1000).toStringAsFixed(2)}s",
                            style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: .6)),
                          ),
                        ],
                      ],
                    ),
                    IconButton(
                      icon: Icon(Icons.logout),
                      onPressed: () async {
                        ref.read(dartWhisperCaptionProvider.notifier).pause();
                        await Future.delayed(Duration(milliseconds: 200));
                        _exitApp();
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openSettings() async {
    debugPrint("open settings");
    final windows = await DesktopMultiWindow.getAllSubWindowIds();
    if (windows.isEmpty) {
      final window = await DesktopMultiWindow.createWindow(jsonEncode({'window_type': 'settings'}));
      window.setTitle("Settings");
      window
        ..setFrame(const Offset(0, 0) & const Size(1700, 1200))
        ..center();
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
      case "launch_url":
        launchUrlString(call.arguments);
        return true;
    }
    return null;
  }

  Future<void> _exitApp() async {
    // close all sub windows
    final subWindowIds = await DesktopMultiWindow.getAllSubWindowIds();
    for (final id in subWindowIds) {
      await WindowController.fromWindowId(id).close();
    }
    // dispose winManager
    await windowManager.destroy();
    exit(0);
  }

  Color _getReasoningColor(int? inMilliseconds, AsyncValue<AppSettingsData> appSettings) {
    final whisperInferenceInterval = (appSettings.value?.inferenceInterval ?? 2000);
    if (inMilliseconds == null || inMilliseconds < whisperInferenceInterval * 0.85) {
      return Colors.white.withValues(alpha: .6);
    }
    if (inMilliseconds < whisperInferenceInterval * 0.95) return Colors.yellow.withValues(alpha: .6);
    return Colors.red.withValues(alpha: .6);
  }

  @override
  Future<void> onWindowClose() async {
    debugPrint("onWindowClose");
    if (await windowManager.isPreventClose()) {
      final windows = await DesktopMultiWindow.getAllSubWindowIds();
      for (final id in windows) {
        await WindowController.fromWindowId(id).close();
      }
      await windowManager.destroy();
      exit(0);
    }
    super.onWindowClose();
  }
}
