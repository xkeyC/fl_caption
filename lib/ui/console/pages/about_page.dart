import 'package:fluent_ui/fluent_ui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/i18n.dart';
import '../../../app/models.dart';
import '../../../app/settings.dart';
import '../../theme.dart';
import '../../widgets.dart';

const _version = '0.2.0';

class AboutPage extends ConsumerWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final runtime = ref.watch(runtimeInfoProvider);
    final paths = ref.watch(appPathsProvider);
    Widget link(String text, String url) =>
        HyperlinkButton(onPressed: () => launchUrl(Uri.parse(url)), child: Text(text));
    return PageScaffold(
      title: tr('关于', 'About'),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Image.asset('assets/icons/app.png', width: 64, height: 64),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('FL Caption', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
                      Text('v$_version', style: TextStyle(color: muted(context))),
                      const SizedBox(height: 6),
                      Text(
                        tr(
                          '离线实时字幕、翻译与字幕文件生成，基于 ONNX Runtime。',
                          'Offline live captions, translation and subtitle files, on ONNX Runtime.',
                        ),
                      ),
                    ],
                  ),
                ),
                link('GitHub', 'https://github.com/xkeyC/fl_caption'),
              ],
            ),
          ),
        ),
        Section(
          title: tr('运行信息', 'Runtime'),
          children: [
            SelectableText(
              [
                'ONNX Runtime: ${runtime.ortPath ?? runtime.error ?? '-'}',
                '${tr('GPU 运行库', 'GPU runtime')}: ${runtime.gpuRuntime ? 'CUDA 12' : tr('无', 'none')}',
                for (final gpu in runtime.gpus) 'GPU: ${gpu.name} (${formatMb(gpu.totalMb.toInt())})',
                '${tr('日志', 'Log')}: ${runtime.logFile}',
                '${tr('设置', 'Settings')}: ${paths.settingsFile}',
              ].join('\n'),
              style: TextStyle(color: muted(context), height: 1.6, fontSize: 12.5),
            ),
          ],
        ),
        Section(
          title: tr('致谢', 'Acknowledgements'),
          children: [
            Text(
              tr(
                '多模态推理基于 local-multimodal-infra 实现，并使用了以下项目和模型（各自沿用其许可证）：',
                'Multimodal inference is built on local-multimodal-infra, with these projects and models (each under its own license):',
              ),
              style: TextStyle(color: muted(context)),
            ),
            Wrap(
              children: [
                link('local-multimodal-infra', 'https://github.com/mercallureAI/local-multimodal-infra'),
                link('ONNX Runtime', 'https://github.com/microsoft/onnxruntime'),
                link('ort', 'https://github.com/pykeio/ort'),
                link('SenseVoice', 'https://github.com/FunAudioLLM/SenseVoice'),
                link('Fun-ASR', 'https://github.com/QwenAudio/Fun-ASR'),
                link('Hy-MT2', 'https://github.com/Tencent-Hunyuan/Hy-MT2'),
                link('Qwen3', 'https://github.com/QwenLM/Qwen3'),
                link('Silero VAD', 'https://github.com/snakers4/silero-vad'),
                link('jieba-rs', 'https://github.com/messense/jieba-rs'),
                link('flutter_rust_bridge', 'https://github.com/fzyzcjy/flutter_rust_bridge'),
              ],
            ),
          ],
        ),
      ],
    );
  }
}
