import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../app/i18n.dart';
import '../app/mobile_protocol.dart';
import '../ui/aurora_background.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'mobile_client.dart';

/// The Android app: sends its microphone or system audio to the desktop,
/// which recognizes and translates it, and shows the captions (also in a
/// floating window over other apps).
Future<void> runMobileApp() async {
  I18n.use('system');
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'fl_caption_microphone',
      channelName: 'Microphone capture',
    ),
    iosNotificationOptions: const IOSNotificationOptions(),
    foregroundTaskOptions: ForegroundTaskOptions(eventAction: ForegroundTaskEventAction.nothing()),
  );
  runApp(const ProviderScope(child: _MobileApp()));
}

class _MobileApp extends StatelessWidget {
  const _MobileApp();

  @override
  Widget build(BuildContext context) {
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
      builder: (context, child) =>
          Stack(fit: StackFit.expand, children: [const AuroraBackground(), child ?? const SizedBox()]),
      home: const _Home(),
    );
  }
}

class _Home extends ConsumerWidget {
  const _Home();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(mobileClientProvider);
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
        children: [
          Row(
            children: [
              Image.asset('assets/icons/app.png', width: 28, height: 28),
              const SizedBox(width: 10),
              Text('FL Caption', style: FluentTheme.of(context).typography.title),
            ],
          ),
          const SizedBox(height: 16),
          if (state.link == Link.connected) const _Session() else const _Connect(),
        ],
      ),
    );
  }
}

/// A label above its control (phones are too narrow for side by side).
class _Field extends StatelessWidget {
  const _Field({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: TextStyle(color: muted(context), fontSize: 13)),
        const SizedBox(height: 6),
        child,
      ],
    ),
  );
}

class _Connect extends HookConsumerWidget {
  const _Connect();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(mobileClientProvider);
    final client = ref.read(mobileClientProvider.notifier);
    final address = useTextEditingController();
    final password = useTextEditingController();
    useEffect(() {
      if (state.host.isNotEmpty && address.text.isEmpty) address.text = '${state.host}:${state.port}';
      if (state.password.isNotEmpty && password.text.isEmpty) password.text = state.password;
      return null;
    }, [state.host, state.password]);

    Future<void> connect() async {
      final target = MobileProtocol.parsePairing(address.text);
      if (target == null) return;
      await client.connect(target.$1, target.$2, password.text.trim());
    }

    Future<void> scan() async {
      final text = await Navigator.of(context).push<String>(FluentPageRoute(builder: (_) => const _ScanPage()));
      final target = text == null ? null : MobileProtocol.parsePairing(text);
      if (target == null) return;
      address.text = '${target.$1}:${target.$2}';
      await connect();
    }

    return Section(
      title: tr('连接电脑', 'Connect to the computer'),
      children: [
        Text(
          tr(
            '在电脑端 FL Caption 的“设置 → 移动 App”中开启连接，然后扫描二维码。手机与电脑需在同一局域网。',
            'On the computer, open FL Caption’s Settings → Mobile app, turn connections on, and scan the code. Both must be on the same network.',
          ),
          style: TextStyle(color: muted(context), fontSize: 13),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 44,
          child: FilledButton(onPressed: scan, child: iconLabel(FluentIcons.q_r_code, tr('扫码连接', 'Scan the code'))),
        ),
        const SizedBox(height: 18),
        _Field(
          label: tr('电脑地址', 'Computer address'),
          child: TextBox(controller: address, placeholder: '192.168.1.10:${MobileProtocol.defaultPort}'),
        ),
        _Field(
          label: tr('连接密码', 'Password'),
          child: TextBox(controller: password, placeholder: tr('电脑端显示的密码', 'As shown on the computer')),
        ),
        Button(
          onPressed: state.link == Link.connecting ? null : connect,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(state.link == Link.connecting ? tr('连接中…', 'Connecting…') : tr('连接', 'Connect')),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: Text(tr('打开 App 时自动连接上次的电脑', 'Connect to the last computer when the app opens'))),
            ToggleSwitch(checked: state.autoConnect, onChanged: client.setAutoConnect),
          ],
        ),
        if (state.error.isNotEmpty) ...[
          const SizedBox(height: 12),
          InfoBar(title: Text(state.error), severity: InfoBarSeverity.error, isLong: true),
        ],
      ],
    );
  }
}

class _ScanPage extends HookWidget {
  const _ScanPage();

  @override
  Widget build(BuildContext context) {
    final done = useRef(false);
    return ScaffoldPage(
      header: PageHeader(
        title: Text(tr('扫描电脑端的二维码', 'Scan the code on the computer')),
        leading: IconButton(icon: const Icon(FluentIcons.back), onPressed: () => Navigator.of(context).pop()),
      ),
      content: MobileScanner(
        onDetect: (capture) {
          final raw = capture.barcodes.firstOrNull?.rawValue;
          if (done.value || raw == null || MobileProtocol.parsePairing(raw) == null) return;
          done.value = true;
          Navigator.of(context).pop(raw);
        },
      ),
    );
  }
}

/// The spoken languages the speech models can be told (empty: detected).
List<(String, String)> _spokenLanguages() => [
  ('', tr('自动检测', 'Detect')),
  ('zh', '中文'),
  ('en', 'English'),
  ('yue', '粤语'),
  ('ja', '日本語'),
  ('ko', '한국어'),
];

class _Session extends ConsumerWidget {
  const _Session();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(mobileClientProvider);
    final client = ref.read(mobileClientProvider.notifier);
    final s = state.settings;
    final statusText = !state.captioning
        ? tr('未开始', 'Stopped')
        : switch (state.status) {
            'loading' => tr('电脑正在加载模型…', 'The computer is loading the models…'),
            'running' => tr('正在识别', 'Listening'),
            'failed' => tr('出错', 'Failed'),
            _ => tr('等待电脑…', 'Waiting for the computer…'),
          };
    Widget choice(String key, List<(String, String)> items) {
      final value = items.any((i) => i.$1 == s[key]) ? s[key]! : (items.isEmpty ? '' : items.first.$1);
      return ComboBox<String>(
        isExpanded: true,
        value: items.isEmpty ? null : value,
        items: [
          for (final (id, name) in items)
            ComboBoxItem(
              value: id,
              child: Text(name, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (v) {
          if (v != null) client.choose(key, v);
        },
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Section(
          title: tr('字幕', 'Captions'),
          trailing: Pill('${state.host}:${state.port}'),
          children: [
            _Field(
              label: tr('采集', 'Capture'),
              child: Segments<AudioInput>(
                value: state.input,
                items: [
                  (AudioInput.microphone, FluentIcons.microphone, tr('麦克风', 'Microphone')),
                  (AudioInput.system, FluentIcons.volume3, tr('系统声音（内录）', 'System audio')),
                ],
                onChanged: client.setInput,
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: FilledButton(
                      onPressed: state.captioning ? client.stopCaptions : client.startCaptions,
                      child: iconLabel(
                        state.captioning ? FluentIcons.stop : FluentIcons.play,
                        state.captioning ? tr('停止', 'Stop') : tr('开始字幕', 'Start captions'),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  height: 44,
                  child: Button(
                    onPressed: client.toggleOverlay,
                    child: iconLabel(
                      FluentIcons.closed_caption,
                      state.overlay ? tr('关闭悬浮窗', 'Hide floating') : tr('悬浮窗', 'Floating'),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(statusText, style: TextStyle(color: muted(context))),
            if (state.error.isNotEmpty) ...[
              const SizedBox(height: 8),
              InfoBar(title: Text(state.error), severity: InfoBarSeverity.error, isLong: true),
            ],
            const SizedBox(height: 12),
            Container(
              constraints: const BoxConstraints(minHeight: 90),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0x66000000), borderRadius: BorderRadius.circular(8)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (state.translation.isNotEmpty)
                    Text(state.translation, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
                  if (state.source.isNotEmpty)
                    Text(state.source, style: TextStyle(fontSize: 14, color: muted(context))),
                  if (state.source.isEmpty && state.translation.isEmpty)
                    Text(tr('字幕会显示在这里', 'Captions appear here'), style: TextStyle(color: muted(context))),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Section(
          title: tr('模型（电脑端同步切换）', 'Models (the computer follows)'),
          children: [
            _Field(label: tr('音频语言', 'Spoken language'), child: choice('spoken', _spokenLanguages())),
            _Field(
              label: tr('目标语言', 'Translate into'),
              child: choice('target', [for (final l in state.languages) (l.id, l.name)]),
            ),
            _Field(
              label: tr('语音模型', 'Speech model'),
              child: choice('asr', [for (final m in state.asr) (m.id, m.name)]),
            ),
            _Field(
              label: tr('翻译模型', 'Translator'),
              child: choice('translator', [for (final m in state.translators) (m.id, m.name)]),
            ),
          ],
        ),
        const SizedBox(height: 14),
        const _OverlaySettings(),
        const SizedBox(height: 14),
        Button(onPressed: client.disconnect, child: Text(tr('断开连接', 'Disconnect'))),
      ],
    );
  }
}

/// The floating window's layout (applied when a slider is let go) and
/// connecting at start.
class _OverlaySettings extends HookConsumerWidget {
  const _OverlaySettings();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(mobileClientProvider);
    final client = ref.read(mobileClientProvider.notifier);
    final history = useState(state.overlayHistory.toDouble());
    final fontSize = useState(state.overlayFontSize);
    useEffect(() {
      history.value = state.overlayHistory.toDouble();
      fontSize.value = state.overlayFontSize;
      return null;
    }, [state.overlayHistory, state.overlayFontSize]);
    return Section(
      title: tr('悬浮窗与连接', 'Floating window and connection'),
      children: [
        _Field(
          label: tr(
            '悬浮窗显示旧句：${history.value.round()} 句',
            'Earlier lines in the floating window: ${history.value.round()}',
          ),
          child: Slider(
            value: history.value,
            min: 0,
            max: 3,
            divisions: 3,
            onChanged: (v) => history.value = v,
            onChangeEnd: (v) => client.setOverlayLayout(history: v.round()),
          ),
        ),
        _Field(
          label: tr('悬浮窗字号：${fontSize.value.round()}', 'Floating window text size: ${fontSize.value.round()}'),
          child: Slider(
            value: fontSize.value,
            min: 14,
            max: 28,
            divisions: 14,
            onChanged: (v) => fontSize.value = v,
            onChangeEnd: (v) => client.setOverlayLayout(fontSize: v.roundToDouble()),
          ),
        ),
        Row(
          children: [
            Expanded(child: Text(tr('打开 App 时自动连接这台电脑', 'Connect to this computer when the app opens'))),
            ToggleSwitch(checked: state.autoConnect, onChanged: client.setAutoConnect),
          ],
        ),
      ],
    );
  }
}
