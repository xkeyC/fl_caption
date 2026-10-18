import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/i18n.dart';
import '../../../app/models.dart';
import '../../../app/settings.dart';
import '../../../src/rust/api/app.dart' as rs_app;
import '../../../src/rust/api/models.dart' as rs;
import '../../theme.dart';
import '../../widgets.dart';

class ModelsPage extends ConsumerWidget {
  const ModelsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final models = ref.watch(modelsProvider);
    final list = models.value ?? const <rs.ModelInfo>[];
    return PageScaffold(
      title: tr('模型', 'Models'),
      subtitle: tr(
        '所有模型都在本机通过 ONNX Runtime 运行；显存为 RTX 4090 实测值，供参考。',
        'Every model runs locally on ONNX Runtime; GPU memory figures were measured on an RTX 4090.',
      ),
      actions: [
        Tooltip(
          message: tr('刷新', 'Refresh'),
          child: IconButton(
            icon: const Icon(FluentIcons.refresh),
            onPressed: () => ref.read(modelsProvider.notifier).refresh(),
          ),
        ),
      ],
      children: [
        const _StorageCard(),
        if (models.hasError) InfoBar(title: Text('${models.error}'), severity: InfoBarSeverity.error),
        Section(
          title: tr('语音识别', 'Speech recognition'),
          children: [
            for (final m in list.where((m) => m.kind == rs.ModelCategory.asr)) _ModelTile(model: m),
            _AsrOptions(models: list),
          ],
        ),
        Section(
          title: tr('翻译', 'Translation'),
          children: [
            for (final m in list.where((m) => m.kind == rs.ModelCategory.translator)) _ModelTile(model: m),
            _TranslatorOptions(models: list),
          ],
        ),
        const _ApiSection(),
      ],
    );
  }
}

/// OpenAI-compatible endpoints people use (base URL, a model name).
const _apiPresets = [
  ('DeepSeek', 'https://api.deepseek.com/v1', 'deepseek-chat'),
  ('OpenAI', 'https://api.openai.com/v1', 'gpt-4o-mini'),
  ('SiliconFlow', 'https://api.siliconflow.cn/v1', 'Qwen/Qwen3-8B'),
  ('Ollama', 'http://127.0.0.1:11434/v1', 'qwen3:8b'),
  ('LM Studio', 'http://127.0.0.1:1234/v1', ''),
];

class _AsrOptions extends ConsumerWidget {
  const _AsrOptions({required this.models});

  final List<rs.ModelInfo> models;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final runtime = ref.watch(runtimeInfoProvider);
    final gpuAvailable = runtime.gpuRuntime && runtime.gpus.isNotEmpty;
    final selected = models.where((m) => m.id == s.asrModel).firstOrNull;
    if (selected == null || selected.gpuOnly) return const SizedBox();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: SwitchRow(
        label: tr('${selected.name} 使用 GPU', 'Run ${selected.name} on the GPU'),
        description: gpuAvailable
            ? tr('NVIDIA CUDA；关闭则在 CPU 上运行', 'NVIDIA CUDA; off runs it on the CPU')
            : tr('未检测到 GPU 运行库或 NVIDIA 显卡', 'No GPU runtime or NVIDIA GPU found'),
        value: s.asrGpu,
        onChanged: (v) => ref.read(settingsProvider.notifier).update((s) => s.copyWith(asrGpu: v)),
      ),
    );
  }
}

class _TranslatorOptions extends ConsumerWidget {
  const _TranslatorOptions({required this.models});

  final List<rs.ModelInfo> models;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final selected = models.where((m) => m.id == s.localTranslator).firstOrNull;
    if (selected == null) return const SizedBox();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: SliderRow(
        label: tr('${selected.name} 上下文长度', '${selected.name} context size'),
        description:
            '${tr('KV 缓存', 'KV cache')} ≈ ${formatMb(selected.kvKbPerToken.toInt() * s.contextTokens / 1024)}'
            '${tr('，更长可参考更多前文', '; longer keeps more earlier lines')}',
        value: s.contextTokens.toDouble(),
        min: 1024,
        max: 8192,
        divisions: 7,
        format: (v) => '${(v / 1024).round()}K',
        onChanged: (v) => ref.read(settingsProvider.notifier).update((s) => s.copyWith(contextTokens: v.round())),
      ),
    );
  }
}

/// The cloud LLM: any OpenAI-compatible chat completions endpoint.
class _ApiSection extends ConsumerWidget {
  const _ApiSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final update = ref.read(settingsProvider.notifier).update;
    return Section(
      title: tr('云端 LLM（OpenAI 兼容 API）', 'Cloud LLM (OpenAI-compatible API)'),
      children: [
        Text(
          tr(
            '在“首页”的翻译模型中选择“云端 API”即可使用；不占用显存。',
            'Pick “Cloud API” as the translator on Home to use it; it needs no GPU memory.',
          ),
          style: TextStyle(color: muted(context), fontSize: 12.5),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (name, url, model) in _apiPresets)
              Button(
                child: Text(name),
                onPressed: () =>
                    update((s) => s.copyWith(apiBaseUrl: url, apiModel: model.isEmpty ? s.apiModel : model)),
              ),
          ],
        ),
        const SizedBox(height: 8),
        SettingRow(
          label: 'Base URL',
          wide: true,
          child: CommitTextField(
            value: s.apiBaseUrl,
            hint: 'https://…/v1',
            onCommit: (v) => update((s) => s.copyWith(apiBaseUrl: v.trim())),
          ),
        ),
        SettingRow(
          label: 'API Key',
          wide: true,
          child: CommitTextField(
            value: s.apiKey,
            obscure: true,
            onCommit: (v) => update((s) => s.copyWith(apiKey: v.trim())),
          ),
        ),
        SettingRow(
          label: tr('模型名', 'Model name'),
          wide: true,
          child: CommitTextField(
            value: s.apiModel,
            onCommit: (v) => update((s) => s.copyWith(apiModel: v.trim())),
          ),
        ),
        SettingRow(
          label: tr('提示词风格', 'Prompt style'),
          description: tr(
            '接口背后是 Hy-MT 等翻译专用模型时选“翻译模型”',
            'Pick “Translation model” when the API serves Hy-MT or a similar model',
          ),
          child: Choice<ApiStyle>(
            value: s.apiStyle,
            items: [
              (ApiStyle.chat, tr('通用对话模型', 'Chat model')),
              (ApiStyle.translationModel, tr('翻译模型', 'Translation model')),
            ],
            onChanged: (v) => update((s) => s.copyWith(apiStyle: v)),
          ),
        ),
      ],
    );
  }
}

final _gpuProvider = FutureProvider.autoDispose<List<rs_app.GpuInfo>>((ref) => rs_app.gpuInfo());

/// GPU, its memory and what the selected models need; the runtime state.
class GpuCard extends ConsumerWidget {
  const GpuCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final runtime = ref.watch(runtimeInfoProvider);
    final gpus = ref.watch(_gpuProvider).value ?? runtime.gpus;
    final s = ref.watch(settingsProvider);
    final models = ref.watch(modelsProvider).value ?? const <rs.ModelInfo>[];
    final estimate = estimateVram(models, s, runtime.cudaContextMb.toInt());
    final gpu = gpus.firstOrNull;
    return Section(
      title: tr('硬件与运行库', 'Hardware and runtime'),
      trailing: Tooltip(
        message: tr('刷新显存', 'Refresh GPU memory'),
        child: IconButton(
          icon: const Icon(FluentIcons.refresh, size: 14),
          onPressed: () => ref.invalidate(_gpuProvider),
        ),
      ),
      children: [
        Row(
          children: [
            Icon(
              runtime.gpuRuntime ? FluentIcons.completed_solid : FluentIcons.info,
              size: 16,
              color: runtime.gpuRuntime ? Colors.green.lighter : Colors.yellow,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                runtime.error != null
                    ? '${tr('ONNX Runtime 加载失败', 'ONNX Runtime not loaded')}: ${runtime.error}'
                    : runtime.gpuRuntime
                    ? tr('GPU 运行库（CUDA 12）已就绪', 'GPU runtime (CUDA 12) ready')
                    : tr(
                        '仅 CPU 运行库：解压 GPU 运行库到程序目录可启用显卡加速',
                        'CPU runtime only: unpack the GPU runtime beside the program to use the GPU',
                      ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (gpu == null)
          Text(tr('未检测到 NVIDIA 显卡', 'No NVIDIA GPU found'), style: TextStyle(color: muted(context)))
        else ...[
          Row(
            children: [
              Expanded(
                child: Text(gpu.name, style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              Text('${tr('驱动', 'Driver')} ${gpu.driver}', style: TextStyle(color: muted(context), fontSize: 12)),
            ],
          ),
          const SizedBox(height: 10),
          _VramBar(total: gpu.totalMb.toInt(), used: gpu.usedMb.toInt(), estimate: estimate),
        ],
      ],
    );
  }
}

class _VramBar extends StatelessWidget {
  const _VramBar({required this.total, required this.used, required this.estimate});

  final int total;
  final int used;
  final int estimate;

  @override
  Widget build(BuildContext context) {
    final usedFraction = (used / total).clamp(0.0, 1.0);
    final estimateFraction = (estimate / total).clamp(0.0, 1.0 - usedFraction);
    final over = used + estimate > total;
    final estimateColor = over ? Colors.red : accent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 12,
            child: Row(
              children: [
                Expanded(
                  flex: (usedFraction * 1000).round(),
                  child: Container(color: Colors.white.withValues(alpha: 0.38)),
                ),
                Expanded(
                  flex: (estimateFraction * 1000).round(),
                  child: Container(color: estimateColor),
                ),
                Expanded(
                  flex: ((1 - usedFraction - estimateFraction) * 1000).round().clamp(0, 1000),
                  child: Container(color: Colors.white.withValues(alpha: 0.08)),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 16,
          children: [
            _Legend(color: Colors.white.withValues(alpha: 0.38), text: '${tr('已占用', 'In use')} ${formatMb(used)}'),
            _Legend(color: estimateColor, text: '${tr('当前选择预计', 'Selected models')} ≈ ${formatMb(estimate)}'),
            _Legend(color: Colors.white.withValues(alpha: 0.08), text: '${tr('总计', 'Total')} ${formatMb(total)}'),
          ],
        ),
        if (over)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              tr(
                '显存可能不足：可关闭其他占用显存的程序，或改用 CPU 识别 / 在线 API 翻译。',
                'GPU memory may not suffice: close other GPU programs, recognize on the CPU or translate through an API.',
              ),
              style: TextStyle(color: Colors.red.lighter, fontSize: 12.5),
            ),
          ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.text});

  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
      ),
      const SizedBox(width: 6),
      Text(text, style: TextStyle(fontSize: 12.5, color: muted(context))),
    ],
  );
}

class _StorageCard extends ConsumerWidget {
  const _StorageCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final paths = ref.watch(appPathsProvider);
    final update = ref.read(settingsProvider.notifier).update;
    final dir = s.modelsDir.isEmpty ? paths.defaultModelsDir : s.modelsDir;
    return Section(
      title: tr('存储与下载', 'Storage and downloads'),
      children: [
        SettingRow(
          label: tr('模型目录', 'Model directory'),
          description: dir,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Button(
                onPressed: () async {
                  final picked = await FilePicker.getDirectoryPath(initialDirectory: dir);
                  if (picked != null) update((s) => s.copyWith(modelsDir: picked));
                },
                child: Text(tr('更改', 'Change')),
              ),
              const SizedBox(width: 6),
              Tooltip(
                message: tr('打开目录', 'Open folder'),
                child: IconButton(icon: const Icon(FluentIcons.folder_open), onPressed: () => _openFolder(dir)),
              ),
            ],
          ),
        ),
        SettingRow(
          label: tr('下载源', 'Download source'),
          description: tr('Hugging Face 访问慢时可选镜像', 'Pick a mirror when Hugging Face is slow'),
          child: Choice<String>(
            value: s.hfEndpoint,
            items: const [('', 'huggingface.co'), ('https://hf-mirror.com', 'hf-mirror.com')],
            onChanged: (v) => update((s) => s.copyWith(hfEndpoint: v)),
          ),
        ),
      ],
    );
  }
}

Future<void> _openFolder(String path) async {
  await Directory(path).create(recursive: true);
  await launchUrl(Uri.file(path));
}

class _ModelTile extends ConsumerWidget {
  const _ModelTile({required this.model});

  final rs.ModelInfo model;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = model;
    final download = ref.watch(downloadsProvider)[m.id];
    final s = ref.watch(settingsProvider);
    final inUse =
        m.id == s.asrModel ||
        (s.translationEnabled && s.translator == TranslatorKind.local && m.id == s.localTranslator);
    final vram = m.vramMb.toInt();
    final downloading = download != null && download.error == null;
    Widget action(IconData icon, String tip, VoidCallback onPressed) => Tooltip(
      message: tip,
      child: IconButton(icon: Icon(icon, size: 14), onPressed: onPressed),
    );

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: inUse ? accent.withValues(alpha: 0.6) : strokeColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Name | CPU / CUDA | GPU memory ... state and actions.
          Row(
            children: [
              Text(m.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              Pill(vram == 0 ? 'CPU' : 'CUDA', color: vram == 0 ? Colors.blue.lighter : Colors.green.lighter),
              const SizedBox(width: 12),
              Text(
                vram == 0 ? tr('不占显存', 'No GPU memory') : '${tr('显存', 'GPU')} ≈ ${formatMb(vram)}',
                style: TextStyle(color: muted(context)),
              ),
              const Spacer(),
              if (downloading)
                Button(
                  onPressed: () => ref.read(downloadsProvider.notifier).cancel(m.id),
                  child: Text(tr('取消', 'Cancel')),
                )
              else if (m.installed) ...[
                if (!inUse) ...[
                  Button(onPressed: () => _use(ref, m), child: Text(tr('使用', 'Use'))),
                  const SizedBox(width: 12),
                ],
                Icon(FluentIcons.completed_solid, size: 14, color: Colors.green.lighter),
                const SizedBox(width: 6),
                Text(tr('已安装', 'Installed')),
                const SizedBox(width: 4),
                action(FluentIcons.folder_open, tr('打开目录', 'Open folder'), () => _openFolder(m.dir)),
                action(
                  FluentIcons.delete,
                  m.imported ? tr('移除导入', 'Remove the import') : tr('删除', 'Delete'),
                  () => _delete(context, ref, m),
                ),
              ] else ...[
                if (m.downloadable)
                  Tooltip(
                    message: formatMb(m.sizeMb.toInt()),
                    child: FilledButton(
                      onPressed: () => ref.read(downloadsProvider.notifier).start(m.id),
                      child: Text(tr('下载', 'Download')),
                    ),
                  ),
                const SizedBox(width: 6),
                Tooltip(
                  message: m.downloadable
                      ? tr('使用已导出的模型目录', 'Use an exported model directory')
                      : tr(
                          '尚未发布下载：导入按 local-multimodal-infra 文档导出的目录',
                          'Not published yet: import a directory exported as local-multimodal-infra describes',
                        ),
                  child: Button(onPressed: () => _import(context, ref, m), child: Text(tr('导入', 'Import'))),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          // The description, or the download's progress.
          if (downloading)
            Row(
              children: [
                Expanded(child: ProgressBar(value: download.fraction == 0 ? null : download.fraction * 100)),
                const SizedBox(width: 12),
                Text(
                  '${formatBytes(download.event.downloaded.toInt())} / ${formatBytes(download.event.total.toInt())}'
                  '  ${formatBytes(download.event.speed.toInt())}/s',
                  style: TextStyle(fontSize: 12, color: muted(context)),
                ),
              ],
            )
          else
            Text(
              download?.error != null
                  ? '${tr('下载失败', 'Download failed')}: ${download!.error}'
                  : (I18n.zh ? m.descriptionZh : m.descriptionEn),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, color: download?.error != null ? Colors.red.lighter : muted(context)),
            ),
        ],
      ),
    );
  }

  void _use(WidgetRef ref, rs.ModelInfo m) {
    final runtime = ref.read(runtimeInfoProvider);
    final gpuAvailable = runtime.gpuRuntime && runtime.gpus.isNotEmpty;
    ref
        .read(settingsProvider.notifier)
        .update(
          (s) => m.kind == rs.ModelCategory.asr
              ? s.copyWith(asrModel: m.id, asrGpu: m.gpuOnly || (!m.cpuOk && gpuAvailable) || s.asrGpu)
              : s.copyWith(translationEnabled: true, translator: TranslatorKind.local, localTranslator: m.id),
        );
  }

  Future<void> _import(BuildContext context, WidgetRef ref, rs.ModelInfo m) async {
    final dir = await FilePicker.getDirectoryPath(dialogTitle: m.name);
    if (dir == null) return;
    try {
      await rs.validateModelDir(id: m.id, dir: dir);
    } catch (error) {
      if (context.mounted) {
        showMessage(
          context,
          '${tr('不是有效的模型目录', 'Not a valid model directory')}: $error',
          severity: InfoBarSeverity.error,
        );
      }
      return;
    }
    ref.read(settingsProvider.notifier).update((s) => s.copyWith(importedModels: {...s.importedModels, m.id: dir}));
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, rs.ModelInfo m) async {
    if (m.imported) {
      ref
          .read(settingsProvider.notifier)
          .update((s) => s.copyWith(importedModels: {...s.importedModels}..remove(m.id)));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => ContentDialog(
        title: Text(tr('删除模型？', 'Delete the model?')),
        content: Text('${m.name}\n${m.dir}'),
        actions: [
          Button(onPressed: () => Navigator.pop(context, false), child: Text(tr('取消', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('删除', 'Delete'))),
        ],
      ),
    );
    if (ok != true) return;
    await rs.deleteModel(id: m.id);
    await ref.read(modelsProvider.notifier).refresh();
  }
}
