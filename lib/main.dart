import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart' as acrylic;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

import 'app/captions.dart';
import 'app/i18n.dart';
import 'app/models.dart';
import 'app/remote_status.dart';
import 'app/settings.dart';
import 'app/tray.dart';
import 'app/window_mode.dart';
import 'app/windows.dart';
import 'src/rust/api/app.dart' as rs_app;
import 'src/rust/frb_generated.dart';
import 'ui/aurora_background.dart';
import 'ui/console/console_shell.dart';
import 'ui/overlay/caption_overlay.dart';
import 'ui/theme.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  final window = await WindowController.fromCurrentEngine();
  final type = windowTypeOf(window.arguments);

  // Every window's engine talks to the same (process-wide) Rust engine.
  await RustLib.init();
  final paths = await _paths();
  final settings = await SettingsNotifier.load(paths.settingsFile);
  I18n.use(settings.uiLanguage);
  // Loads ONNX Runtime once per process; later calls return the same state.
  final runtime = await rs_app.initEngine(logDir: paths.logDir, searchRoots: [Directory.current.path]);
  configureModelStore(settings, paths);

  final container = ProviderContainer(
    overrides: [
      appPathsProvider.overrideWithValue(paths),
      initialSettingsProvider.overrideWithValue(settings),
      runtimeInfoProvider.overrideWithValue(runtime),
    ],
  );
  if (type == WindowTypes.settings) {
    await _runSettingsWindow(window, container);
  } else {
    await _runCaptionWindow(container, settings);
  }
}

Future<AppPaths> _paths() async {
  final sep = Platform.pathSeparator;
  final exeDir = File(Platform.resolvedExecutable).parent.path;
  final support = (await getApplicationSupportDirectory()).path;
  // Portable layout first: models/ beside the program (like the runtime).
  final portableModels = Directory('$exeDir${sep}models');
  return AppPaths(
    supportDir: support,
    vadModel: '$exeDir${sep}data${sep}flutter_assets${sep}assets${sep}models${sep}silero_vad.onnx',
    defaultModelsDir: portableModels.existsSync() ? portableModels.path : '$support${sep}models',
  );
}

// ------------------------------------------------------------------ caption bar

Future<void> _runCaptionWindow(ProviderContainer container, AppSettings settings) async {
  if (Platform.isWindows) await acrylic.Window.initialize();
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(title: 'FL Caption', titleBarStyle: TitleBarStyle.hidden, backgroundColor: Colors.transparent),
  );
  await container.read(overlayProvider.notifier).setUp();
  await windowManager.show();
  await AppTray.install(container);

  final captions = container.read(captionProvider.notifier);
  await mainChannel.setMethodCallHandler((call) async {
    switch (call.method) {
      case 'settings_changed':
        final json = jsonDecode(call.arguments as String) as Map<String, dynamic>;
        container.read(settingsProvider.notifier).receive(AppSettings.fromJson(json));
        return null;
      case 'caption_status':
        return <String, dynamic>{...captions.statusMap(container.read(captionProvider))};
      case 'caption_toggle':
        await captions.toggle();
      case 'caption_start':
        await captions.start();
      case 'caption_restart':
        if (container.read(captionProvider).active) await captions.start();
      case 'context_clear':
        await captions.clearContext();
      case 'context_export':
        await captions.exportContext();
      case 'show_caption_bar':
        await windowManager.show();
        return null;
    }
    return null;
  });

  runApp(UncontrolledProviderScope(container: container, child: const CaptionApp()));

  // First run (no speech model yet): open the settings on the models page.
  // Otherwise captions that were on when the app quit start again.
  final models = await container.read(modelsProvider.future);
  final asr = models.where((m) => m.id == settings.asrModel).firstOrNull;
  if (asr == null || !asr.installed) {
    await openSettingsWindow(page: modelsPageIndex);
  } else if (settings.captionsOn) {
    await captions.start();
  }
  // Development: open the settings at start, on page N if a number is given.
  final openSettings = Platform.environment['FL_CAPTION_OPEN_SETTINGS'];
  if (openSettings != null) {
    await openSettingsWindow(page: int.tryParse(openSettings) ?? 0);
  }
}

FluentApp _fluentApp({required Widget home, Widget Function(Widget child)? background}) {
  return FluentApp(
    debugShowCheckedModeBanner: false,
    title: 'FL Caption',
    themeMode: ThemeMode.dark,
    darkTheme: buildTheme(),
    theme: buildTheme(),
    locale: I18n.zh ? const Locale('zh', 'CN') : const Locale('en'),
    supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
      FluentLocalizations.delegate,
    ],
    color: Colors.transparent,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
      child: background == null ? child ?? const SizedBox() : background(child ?? const SizedBox()),
    ),
    home: home,
  );
}

class CaptionApp extends ConsumerWidget {
  const CaptionApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    I18n.use(ref.watch(settingsProvider.select((s) => s.uiLanguage)));
    return _fluentApp(home: const _CaptionWindowEvents(child: CaptionOverlay()));
  }
}

/// Remembers where the bar was moved; closing it quits the app.
class _CaptionWindowEvents extends ConsumerStatefulWidget {
  const _CaptionWindowEvents({required this.child});

  final Widget child;

  @override
  ConsumerState<_CaptionWindowEvents> createState() => _CaptionWindowEventsState();
}

class _CaptionWindowEventsState extends ConsumerState<_CaptionWindowEvents> with WindowListener {
  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    windowManager.setPreventClose(true);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMoved() => ref.read(overlayProvider.notifier).saveBounds();

  @override
  void onWindowResized() => ref.read(overlayProvider.notifier).saveBounds();

  @override
  Future<void> onWindowClose() => quitApp(ref.read(captionProvider.notifier));

  @override
  Widget build(BuildContext context) => widget.child;
}

Future<void> quitApp(CaptionController captions) async {
  await captions.stop(remember: false).timeout(const Duration(seconds: 5), onTimeout: () {});
  // A sub window may be closing already (and never answer).
  try {
    for (final controller in await WindowController.getAll().timeout(const Duration(seconds: 1))) {
      if (windowTypeOf(controller.arguments) != WindowTypes.main) {
        await controller.invokeMethod('window_close').timeout(const Duration(seconds: 1), onTimeout: () => null);
      }
    }
  } catch (_) {}
  await AppTray.remove();
  await windowManager.setPreventClose(false);
  await windowManager.destroy();
  exit(0);
}

// ------------------------------------------------------------------ settings window

Future<void> _runSettingsWindow(WindowController window, ProviderContainer container) async {
  await window.handleWindowCalls();
  SettingsNotifier.sendToMainWindow = true;
  final arguments = jsonDecode(window.arguments) as Map;
  container.read(consolePageProvider.notifier).select((arguments['page'] as int?) ?? 0);
  await settingsChannel.setMethodCallHandler((call) async {
    switch (call.method) {
      case 'caption_status':
        container.read(remoteStatusProvider.notifier).receive(Map<String, dynamic>.from(call.arguments as Map));
      case 'select_page':
        container.read(consolePageProvider.notifier).select(call.arguments as int);
    }
    return null;
  });
  container.read(remoteStatusProvider.notifier).refresh();

  await windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: false);
  await windowManager.setTitle(tr('FL Caption 设置', 'FL Caption settings'));
  await windowManager.setSize(const Size(1180, 800));
  await windowManager.setMinimumSize(const Size(960, 640));
  await windowManager.center();
  runApp(UncontrolledProviderScope(container: container, child: const SettingsApp()));
}

class SettingsApp extends ConsumerWidget {
  const SettingsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    I18n.use(ref.watch(settingsProvider.select((s) => s.uiLanguage)));
    return _fluentApp(
      home: const ConsoleShell(),
      background: (child) => Stack(fit: StackFit.expand, children: [const AuroraBackground(), child]),
    );
  }
}
