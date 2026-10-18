import 'package:fluent_ui/fluent_ui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../app/i18n.dart';
import '../../../app/settings.dart';
import '../../widgets.dart';

const _colors = [0xFFFFFFFF, 0xFFFFF3B0, 0xFFB8F0FF, 0xFFC8FFC8, 0xFFFFC8E6];

class AppearancePage extends ConsumerWidget {
  const AppearancePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final update = ref.read(settingsProvider.notifier).update;
    return PageScaffold(
      title: tr('字幕外观', 'Caption style'),
      children: [
        _Preview(settings: s),
        Section(
          title: tr('内容', 'Content'),
          children: [
            SettingRow(
              label: tr('显示', 'Show'),
              child: Choice<CaptionLines>(
                value: s.captionLines,
                items: [
                  (CaptionLines.both, tr('原文 + 译文', 'Source and translation')),
                  (CaptionLines.translationOnly, tr('仅译文', 'Translation only')),
                  (CaptionLines.sourceOnly, tr('仅原文', 'Source only')),
                ],
                onChanged: (v) => update((s) => s.copyWith(captionLines: v)),
              ),
            ),
            SwitchRow(
              label: tr('译文在上', 'Translation on top'),
              value: s.translationFirst,
              onChanged: (v) => update((s) => s.copyWith(translationFirst: v)),
            ),
            SliderRow(
              label: tr('保留上一句', 'Earlier lines shown'),
              value: s.historyLines.toDouble(),
              min: 0,
              max: 3,
              divisions: 3,
              format: (v) => '${v.round()}',
              onChanged: (v) => update((s) => s.copyWith(historyLines: v.round())),
            ),
          ],
        ),
        Section(
          title: tr('样式', 'Style'),
          children: [
            SliderRow(
              label: tr('译文字号', 'Translation size'),
              value: s.translationFontSize,
              min: 14,
              max: 48,
              divisions: 34,
              format: (v) => '${v.round()}',
              onChanged: (v) => update((s) => s.copyWith(translationFontSize: v)),
            ),
            SliderRow(
              label: tr('原文字号', 'Source size'),
              value: s.sourceFontSize,
              min: 10,
              max: 36,
              divisions: 26,
              format: (v) => '${v.round()}',
              onChanged: (v) => update((s) => s.copyWith(sourceFontSize: v)),
            ),
            SliderRow(
              label: tr('背景不透明度', 'Background opacity'),
              value: s.backgroundOpacity,
              min: 0,
              max: 1,
              divisions: 20,
              format: (v) => '${(v * 100).round()}%',
              onChanged: (v) => update((s) => s.copyWith(backgroundOpacity: v)),
            ),
            SettingRow(
              label: tr('文字颜色', 'Text colour'),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final c in _colors)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: GestureDetector(
                        onTap: () => update((s) => s.copyWith(textColor: c)),
                        child: Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: Color(c),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: s.textColor == c ? Colors.white : Colors.white.withValues(alpha: 0.24),
                              width: s.textColor == c ? 3 : 1,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            SwitchRow(
              label: tr('悬停时显示状态', 'Show status on hover'),
              value: s.showStatus,
              onChanged: (v) => update((s) => s.copyWith(showStatus: v)),
            ),
          ],
        ),
        Section(
          title: tr('通用', 'General'),
          children: [
            SettingRow(
              label: tr('界面语言', 'Language'),
              child: Choice<String>(
                value: s.uiLanguage,
                items: const [('system', 'System / 系统'), ('zh', '简体中文'), ('en', 'English')],
                onChanged: (v) => update((s) => s.copyWith(uiLanguage: v)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final s = settings;
    final color = Color(s.textColor);
    final source = Text(
      'The other local beer is called Manta',
      style: TextStyle(fontSize: s.sourceFontSize, color: color.withValues(alpha: 0.8)),
    );
    final translation = Text(
      '另一款本地啤酒叫做“曼塔”',
      style: TextStyle(fontSize: s.translationFontSize, color: color, fontWeight: FontWeight.w500),
    );
    final lines = switch (s.captionLines) {
      CaptionLines.both => s.translationFirst ? [translation, source] : [source, translation],
      CaptionLines.translationOnly => [translation],
      CaptionLines.sourceOnly => [source],
    };
    return Container(
      height: 150,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const LinearGradient(colors: [Color(0xFF3A4A6B), Color(0xFF6B4A3A)]),
      ),
      alignment: Alignment.center,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 40),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: s.backgroundOpacity),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: lines),
      ),
    );
  }
}
