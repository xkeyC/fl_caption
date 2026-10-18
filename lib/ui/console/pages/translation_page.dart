import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../app/captions.dart';
import '../../../app/i18n.dart';
import '../../../app/settings.dart';
import '../../../src/rust/api/caption.dart' as rs;
import '../../theme.dart';
import '../../widgets.dart';

class TranslationPage extends ConsumerWidget {
  const TranslationPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final update = ref.read(settingsProvider.notifier).update;

    return PageScaffold(
      title: tr('翻译', 'Translation'),
      subtitle: tr(
        '怎样翻译：实时翻译、参考前文与背景说明。翻译模型与云端 API 在“首页”切换、在“模型”页配置。',
        'How lines are translated: live translation, context and background. Pick the translator on Home, set it up on Models.',
      ),
      children: [
        Section(
          title: tr('实时翻译', 'Live translation'),
          children: [
            SwitchRow(
              label: tr('翻译正在说的句子', 'Translate the line being spoken'),
              description: tr(
                '边说边翻，句子结束后再给出最终译文；关闭可省一半计算',
                'Translate while the line grows, then once more when it ends; off halves the work',
              ),
              value: s.translatePartials,
              onChanged: (v) => update((s) => s.copyWith(translatePartials: v)),
            ),
            SwitchRow(
              label: tr('同语言不翻译', 'Skip lines already in the target language'),
              description: tr(
                '识别出的语言与目标语言相同时直接显示原文',
                'Shows lines as they are when they are already in the target language',
              ),
              value: s.skipSameLanguage,
              onChanged: (v) => update((s) => s.copyWith(skipSameLanguage: v)),
            ),
            SliderRow(
              label: tr('参考前文', 'Earlier lines as context'),
              description: tr(
                '更多前文让称呼与术语更一致，但也可能把上一句的内容带进来',
                'More context keeps names and terms consistent, but can carry earlier content over',
              ),
              value: s.contextLines.toDouble(),
              min: 0,
              max: 12,
              divisions: 12,
              format: (v) => tr('${v.round()} 句', '${v.round()} lines'),
              onChanged: (v) => update((s) => s.copyWith(contextLines: v.round())),
            ),
            SliderRow(
              label: tr('随机性', 'Temperature'),
              description: tr('0 最稳定（推荐，减少字幕跳变）', '0 is the most stable (recommended: less flicker)'),
              value: s.temperature,
              min: 0,
              max: 1,
              divisions: 10,
              format: (v) => v.toStringAsFixed(1),
              onChanged: (v) => update((s) => s.copyWith(temperature: v)),
            ),
          ],
        ),
        Section(
          title: tr('背景说明', 'About the content'),
          children: [
            Text(
              tr(
                '告诉翻译这是什么内容（会议、讲座、动画……）与风格要求，例如：“技术分享会，产品名保留英文，口语化”。',
                'Tell the translator what this is (a meeting, a talk, an anime…) and the style, e.g. “A tech talk; keep product names in English, casual”.',
              ),
              style: TextStyle(color: muted(context), fontSize: 12.5),
            ),
            const SizedBox(height: 8),
            CommitTextField(
              value: s.background,
              maxLines: 4,
              hint: tr('可留空', 'Optional'),
              onCommit: (v) => update((s) => s.copyWith(background: v)),
            ),
          ],
        ),
        _TestSection(settings: s),
      ],
    );
  }
}

class _TestSection extends HookConsumerWidget {
  const _TestSection({required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = useTextEditingController(
      text: "Let's move the meeting to Thursday afternoon and share the slides before then.",
    );
    final result = useState<String?>(null);
    final busy = useState(false);
    final translation = translationSettingsOf(settings.copyWith(translationEnabled: true));
    return Section(
      title: tr('试一试', 'Try it'),
      children: [
        Row(
          children: [
            Expanded(child: TextBox(controller: text)),
            const SizedBox(width: 12),
            FilledButton(
              onPressed: busy.value || translation == null
                  ? null
                  : () async {
                      busy.value = true;
                      result.value = tr('翻译中…（首次需要加载模型）', 'Translating… (the first time loads the model)');
                      try {
                        final out = await rs.testTranslation(settings: translation, text: text.text);
                        result.value =
                            '${out.text}\n\n${tr('首字', 'First token')} ${out.firstTokenMs} ms · ${tr('总计', 'total')} ${out.totalMs} ms';
                      } catch (error) {
                        result.value = '${tr('失败', 'Failed')}: $error';
                      } finally {
                        busy.value = false;
                      }
                    },
              child: Text(tr('翻译', 'Translate')),
            ),
          ],
        ),
        if (result.value != null) ...[
          const SizedBox(height: 10),
          SelectableText(result.value!, style: const TextStyle(height: 1.5)),
        ],
      ],
    );
  }
}
