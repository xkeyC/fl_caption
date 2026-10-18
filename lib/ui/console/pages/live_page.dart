import 'package:fluent_ui/fluent_ui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../app/remote_status.dart';
import '../../../app/i18n.dart';
import '../../../app/models.dart';
import '../../../app/settings.dart';
import '../../../src/rust/api/app.dart' as rs_app;
import '../../../src/rust/api/models.dart' as rs;
import '../../theme.dart';
import '../../widgets.dart';
import '../console_shell.dart';
import 'mobile_page.dart' show mobileStatusProvider;
import 'models_page.dart' show GpuCard;

/// Listed again whenever the home page is shown (devices come and go).
final audioDevicesProvider = FutureProvider.autoDispose<List<rs_app.AudioDevice>>((ref) => rs_app.audioDevices());

/// The home page: start and stop, and the settings people switch most
/// (languages, audio input, models). Everything else about the models is on
/// the Models page.
class LivePage extends ConsumerWidget {
  const LivePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    return PageScaffold(
      title: tr('首页', 'Home'),
      subtitle: tr(
        '识别电脑正在播放的声音或麦克风，边说边出字幕并实时翻译。',
        'Captions what the computer plays or the microphone hears, translated as it is spoken.',
      ),
      children: [
        const GpuCard(),
        const _ControlCard(),
        _QuickSettings(settings: s),
        _AdvancedCard(settings: s),
      ],
    );
  }
}

/// SenseVoice and Fun-ASR-Nano: the languages they can be told.
List<(String, String)> _spokenLanguages(rs.ModelInfo? model) {
  final codes = model?.hotwords ?? false ? const ['zh', 'en', 'ja'] : const ['zh', 'en', 'yue', 'ja', 'ko'];
  const names = {'zh': '中文', 'en': 'English', 'yue': '粤语', 'ja': '日本語', 'ko': '한국어'};
  return [('', tr('自动检测', 'Detect')), for (final c in codes) (c, names[c]!)];
}

class _QuickSettings extends ConsumerWidget {
  const _QuickSettings({required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = settings;
    final update = ref.read(settingsProvider.notifier).update;
    final models = ref.watch(modelsProvider).value ?? const <rs.ModelInfo>[];
    final runtime = ref.watch(runtimeInfoProvider);
    final gpuAvailable = runtime.gpuRuntime && runtime.gpus.isNotEmpty;
    final asrModels = models.where((m) => m.kind == rs.ModelCategory.asr).toList();
    final translators = models.where((m) => m.kind == rs.ModelCategory.translator).toList();
    final asr = asrModels.where((m) => m.id == s.asrModel).firstOrNull;
    final spoken = _spokenLanguages(asr);
    final languages = rs_app.languages();
    String label(rs.ModelInfo m) => '${m.name}${m.installed ? '' : tr('（未安装）', ' (not installed)')}';

    final translator = !s.translationEnabled
        ? 'off'
        : s.translator == TranslatorKind.api
        ? 'api'
        : s.localTranslator;
    final apiName = s.apiModel.isNotEmpty ? s.apiModel : tr('未配置', 'not set up');

    return Section(
      title: tr('快捷设置', 'Quick settings'),
      children: [
        SettingRow(
          label: tr('音频语言', 'Spoken language'),
          description: tr('指定后识别更准；混合语言时选自动检测', 'More accurate when set; pick Detect for mixed speech'),
          child: Choice<String>(
            value: spoken.any((l) => l.$1 == s.asrLanguage) ? s.asrLanguage : '',
            items: spoken,
            onChanged: (v) => update((s) => s.copyWith(asrLanguage: v)),
          ),
        ),
        SettingRow(
          label: tr('目标语言', 'Translate into'),
          child: Choice<String>(
            value: s.targetLanguage,
            items: [for (final l in languages) (l.code, '${l.native}  ·  ${I18n.zh ? l.zh : l.en}')],
            onChanged: (v) => update((s) => s.copyWith(targetLanguage: v)),
          ),
        ),
        const _InputRow(),
        SettingRow(
          label: tr('语音模型', 'Speech model'),
          description: asr == null || asr.installed
              ? null
              : tr('未安装：请在“模型”页下载', 'Not installed: download it on the Models page'),
          child: Choice<String>(
            value: s.asrModel,
            items: [for (final m in asrModels) (m.id, label(m))],
            onChanged: (v) {
              final model = asrModels.firstWhere((m) => m.id == v);
              update(
                (s) => s.copyWith(asrModel: v, asrGpu: model.gpuOnly || (!model.cpuOk && gpuAvailable) || s.asrGpu),
              );
            },
          ),
        ),
        SettingRow(
          label: tr('翻译模型', 'Translator'),
          description: s.translationEnabled && s.translator == TranslatorKind.api && s.apiBaseUrl.isEmpty
              ? tr('云端 API 尚未配置：请在“模型”页填写', 'The cloud API is not set up: fill it in on the Models page')
              : null,
          child: Choice<String>(
            value: translator,
            items: [
              ('off', tr('不翻译', 'Off')),
              for (final m in translators) (m.id, label(m)),
              ('api', '${tr('云端 API', 'Cloud API')} · $apiName'),
            ],
            onChanged: (v) => update(
              (s) => switch (v) {
                'off' => s.copyWith(translationEnabled: false),
                'api' => s.copyWith(translationEnabled: true, translator: TranslatorKind.api),
                _ => s.copyWith(translationEnabled: true, translator: TranslatorKind.local, localTranslator: v),
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _ControlCard extends ConsumerWidget {
  const _ControlCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final captions = ref.watch(remoteStatusProvider);
    final remote = ref.read(remoteStatusProvider.notifier);
    final s = ref.watch(settingsProvider);
    final models = ref.watch(modelsProvider).value ?? const <rs.ModelInfo>[];
    final runtime = ref.watch(runtimeInfoProvider);
    final asr = models.where((m) => m.id == s.asrModel).firstOrNull;
    final ready = asr?.installed ?? false;
    final vram = estimateVram(models, s, runtime.cudaContextMb.toInt());
    final statusText = switch (captions.status) {
      'loading' =>
        captions.message == 'translator'
            ? tr('正在加载翻译模型…', 'Loading the translator…')
            : tr('正在加载语音模型…', 'Loading the speech model…'),
      'running' => tr('正在识别', 'Listening'),
      'failed' => tr('出错', 'Failed'),
      _ => tr('未运行', 'Stopped'),
    };
    return Section(
      title: tr('控制', 'Control'),
      children: [
        Row(
          children: [
            SizedBox(
              height: 40,
              child: FilledButton(
                onPressed: ready || captions.active ? () => remote.call('caption_toggle') : null,
                child: iconLabel(
                  captions.active ? FluentIcons.stop : FluentIcons.play,
                  captions.active ? tr('停止', 'Stop') : tr('开始字幕', 'Start captions'),
                ),
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (captions.status == 'loading') ...[
                        const SizedBox(width: 14, height: 14, child: ProgressRing(strokeWidth: 2)),
                        const SizedBox(width: 8),
                      ],
                      Text(statusText, style: const TextStyle(fontWeight: FontWeight.w600)),
                      if (captions.provider.isNotEmpty) Pill(captions.provider.toUpperCase()),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    captions.device.isNotEmpty
                        ? captions.device
                        : vram > 0
                        ? '${tr('预计显存', 'Estimated GPU memory')} ≈ ${formatMb(vram)}'
                        : tr('CPU 运行，不占用显存', 'Runs on the CPU, no GPU memory'),
                    style: TextStyle(color: muted(context), fontSize: 12.5),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Text(
              tr('已记录 ${captions.lines} 句', '${captions.lines} lines kept'),
              style: TextStyle(color: muted(context)),
            ),
            const SizedBox(width: 10),
            Button(
              onPressed: () => remote.call('context_export'),
              child: iconLabel(FluentIcons.download, tr('导出上下文', 'Export context')),
            ),
            const SizedBox(width: 8),
            Button(
              onPressed: () => remote.call('context_clear'),
              child: iconLabel(FluentIcons.broom, tr('清理上下文', 'Clear context')),
            ),
          ],
        ),
        if (!ready) ...[
          const SizedBox(height: 12),
          InfoBar(
            title: Text(tr('所选语音模型尚未安装', 'The selected speech model is not installed')),
            severity: InfoBarSeverity.warning,
            action: HyperlinkButton(
              onPressed: () => ref.read(consolePageProvider.notifier).select(modelsPageIndex),
              child: Text(tr('前往模型页', 'Open Models')),
            ),
          ),
        ],
        if (captions.status == 'failed' && captions.message.isNotEmpty) ...[
          const SizedBox(height: 12),
          InfoBar(
            title: Text(tr('出错', 'Failed')),
            content: Text(captions.message),
            severity: InfoBarSeverity.error,
            isLong: true,
          ),
        ] else if (captions.lastError.isNotEmpty) ...[
          const SizedBox(height: 12),
          InfoBar(
            title: Text(tr('错误', 'Error')),
            content: Text(captions.lastError),
            severity: InfoBarSeverity.error,
            isLong: true,
          ),
        ],
      ],
    );
  }
}

/// The audio input: what a playback device plays (loopback) or a
/// microphone, in one list.
class _InputRow extends ConsumerWidget {
  const _InputRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final phone = ref.watch(mobileStatusProvider.select((m) => m.client));
    if (phone.isNotEmpty) {
      return SettingRow(
        label: tr('输入设备', 'Audio input'),
        description: tr(
          '手机 App 已接入，电脑暂停录音；断开后恢复',
          'The phone app is connected: this computer stops recording until it leaves',
        ),
        child: Choice<String>(
          value: 'phone',
          items: [('phone', '${tr('手机 App', 'Phone app')} · $phone')],
          onChanged: null,
        ),
      );
    }
    final devices = ref.watch(audioDevicesProvider).value ?? const [];
    final system = tr('系统声音', 'System audio');
    final microphone = tr('麦克风', 'Microphone');
    final defaultName = tr('默认设备', 'default device');
    final items = <(String, String)>[
      ('system|', '$system · $defaultName'),
      for (final d in devices.where((d) => d.kind == rs_app.AudioSourceKind.system && d.id.isNotEmpty))
        ('system|${d.id}', '$system · ${d.name}'),
      ('microphone|', '$microphone · $defaultName'),
      for (final d in devices.where((d) => d.kind == rs_app.AudioSourceKind.microphone && d.id.isNotEmpty))
        ('microphone|${d.id}', '$microphone · ${d.name}'),
    ];
    final current = '${s.audioSource}|${s.deviceId}';
    return SettingRow(
      label: tr('输入设备', 'Audio input'),
      description: s.audioSource == 'system'
          ? tr('录制该设备正在播放的声音（回环）', 'Records what the device plays (loopback)')
          : null,
      child: Choice<String>(
        value: items.any((i) => i.$1 == current) ? current : '${s.audioSource}|',
        items: items,
        onChanged: (v) {
          final split = v.indexOf('|');
          ref
              .read(settingsProvider.notifier)
              .update((s) => s.copyWith(audioSource: v.substring(0, split), deviceId: v.substring(split + 1)));
        },
      ),
    );
  }
}

class _AdvancedCard extends ConsumerWidget {
  const _AdvancedCard({required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = settings;
    final update = ref.read(settingsProvider.notifier).update;
    return Expander(
      header: Text(tr('高级：断句与实时性', 'Advanced: segmentation and latency')),
      content: Column(
        children: [
          SliderRow(
            label: tr('实时刷新间隔', 'Partial caption interval'),
            description: tr('说话时多久更新一次正在识别的字幕', 'How often the line being spoken is updated'),
            value: s.partialIntervalMs.toDouble(),
            min: 200,
            max: 1500,
            divisions: 13,
            format: (v) => '${v.round()} ms',
            onChanged: (v) => update((s) => s.copyWith(partialIntervalMs: v.round())),
          ),
          SliderRow(
            label: tr('断句停顿', 'Pause that ends a line'),
            value: s.minSilenceMs.toDouble(),
            min: 200,
            max: 1500,
            divisions: 13,
            format: (v) => '${v.round()} ms',
            onChanged: (v) => update((s) => s.copyWith(minSilenceMs: v.round())),
          ),
          SliderRow(
            label: tr('单句最长（缓冲容量）', 'Longest line (buffer size)'),
            description: tr('一直不停顿时，最长多久强制断句', 'Speech without a pause is cut after this long'),
            value: s.maxSegmentMs / 1000,
            min: 4,
            max: 25,
            divisions: 21,
            format: (v) => '${v.round()} s',
            onChanged: (v) => update((s) => s.copyWith(maxSegmentMs: (v * 1000).round())),
          ),
          SwitchRow(
            label: tr('语音检测（VAD）', 'Voice activity detection (VAD)'),
            description: tr(
              '关闭后所有声音都送去识别，按识别出的整句断句，定稿约慢 1 秒，安静时可能冒出零星单词；背景音很吵、人声常被漏掉时可以关掉',
              'Off: everything heard is transcribed and lines end at finished sentences, about 1 s later, with the odd stray word in quiet passages; try it when loud background sound hides speech',
            ),
            value: s.vadEnabled,
            onChanged: (v) => update((s) => s.copyWith(vadEnabled: v)),
          ),
          if (s.vadEnabled)
            SliderRow(
              label: tr('语音检测阈值', 'Speech detection threshold'),
              description: tr(
                '越低越容易听到嘈杂背景里的人声，越高越不容易把噪音当成语音',
                'Lower hears speech under loud background sound; higher ignores more noise',
              ),
              value: s.vadThreshold,
              min: 0.05,
              max: 0.95,
              divisions: 18,
              format: (v) => v.toStringAsFixed(2),
              onChanged: (v) => update((s) => s.copyWith(vadThreshold: v)),
            ),
          SwitchRow(
            label: tr('弱音增强', 'Boost quiet audio'),
            description: tr('音量很小时自动放大；可能把短停顿连成一句', 'Raises very quiet input; may join sentences across short pauses'),
            value: s.autoGain,
            onChanged: (v) => update((s) => s.copyWith(autoGain: v)),
          ),
        ],
      ),
    );
  }
}
