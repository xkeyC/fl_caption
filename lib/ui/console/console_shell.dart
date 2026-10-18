import 'package:fluent_ui/fluent_ui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../app/remote_status.dart';
import '../../app/i18n.dart';
import '../theme.dart';
import '../widgets.dart';
import 'pages/about_page.dart';
import 'pages/appearance_page.dart';
import 'pages/files_page.dart';
import 'pages/glossary_page.dart';
import 'pages/live_page.dart';
import 'pages/mobile_page.dart';
import 'pages/models_page.dart';
import 'pages/translation_page.dart';

class _Page {
  const _Page(this.icon, this.label, this.builder);

  final IconData icon;
  final String Function() label;
  final Widget Function() builder;
}

/// The Models page's index (opened at the first start).
const modelsPageIndex = 4;

final _pages = [
  _Page(FluentIcons.home, () => tr('首页', 'Home'), () => const LivePage()),
  _Page(FluentIcons.video, () => tr('文件', 'Files'), () => const FilesPage()),
  _Page(FluentIcons.translate, () => tr('翻译', 'Translate'), () => const TranslationPage()),
  _Page(FluentIcons.dictionary, () => tr('术语', 'Glossary'), () => const GlossaryPage()),
  _Page(FluentIcons.processing, () => tr('模型', 'Models'), () => const ModelsPage()),
  _Page(FluentIcons.color, () => tr('外观', 'Style'), () => const AppearancePage()),
  _Page(FluentIcons.cell_phone, () => tr('移动 App', 'Mobile'), () => const MobilePage()),
  _Page(FluentIcons.info, () => tr('关于', 'About'), () => const AboutPage()),
];

class ConsolePage extends Notifier<int> {
  @override
  int build() => 0;

  void select(int index) => state = index;
}

final consolePageProvider = NotifierProvider<ConsolePage, int>(ConsolePage.new);

/// The normal window: our own title bar, the page rail, the page panel.
class ConsoleShell extends ConsumerWidget {
  const ConsoleShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(consolePageProvider);
    final theme = FluentTheme.of(context);
    const shape = RoundedRectangleBorder(
      side: BorderSide(color: strokeColor),
      borderRadius: BorderRadius.only(topLeft: Radius.circular(8)),
    );
    return NavigationView(
      titleBar: const _TitleBar(),
      content: Row(
        children: [
          _Rail(index: index, onSelect: (i) => ref.read(consolePageProvider.notifier).select(i)),
          Expanded(
            child: DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: const ShapeDecoration(shape: shape),
              child: ClipPath(
                clipper: const ShapeBorderClipper(shape: shape),
                child: ColoredBox(
                  color: panelColor,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _ApplyModelsBanner(),
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: theme.fastAnimationDuration,
                          switchInCurve: theme.animationCurve,
                          switchOutCurve: theme.animationCurve,
                          layoutBuilder: (child, children) => SizedBox(child: child),
                          transitionBuilder: (child, animation) =>
                              EntrancePageTransition(animation: animation, child: child),
                          child: KeyedSubtree(key: ValueKey(index), child: _pages[index].builder()),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown while the running captions use other models than the selected
/// ones: applying restarts them, unloading the old models and loading the
/// new ones.
class _ApplyModelsBanner extends ConsumerWidget {
  const _ApplyModelsBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final captions = ref.watch(remoteStatusProvider);
    if (!captions.pending) return const SizedBox();
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 14, 28, 0),
      child: InfoBar(
        title: Text(tr('模型已更改', 'Models changed')),
        content: Text(
          tr(
            '字幕仍在使用之前的模型。立即应用会卸载旧模型并载入新模型，字幕将短暂中断。',
            'Captions still use the previous models. Applying unloads them and loads the new ones; captions pause briefly.',
          ),
        ),
        severity: InfoBarSeverity.info,
        isLong: true,
        action: FilledButton(
          onPressed: () => ref.read(remoteStatusProvider.notifier).call('caption_restart'),
          child: Text(tr('立即应用', 'Apply now')),
        ),
      ),
    );
  }
}

class _TitleBar extends ConsumerWidget {
  const _TitleBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final captions = ref.watch(remoteStatusProvider);
    return SizedBox(
      height: 46,
      child: Row(
        children: [
          const SizedBox(width: 16),
          Expanded(
            child: DragToMoveArea(
              child: Row(
                children: [
                  Image.asset('assets/icons/app.png', width: 20, height: 20),
                  const SizedBox(width: 12),
                  const Text('FL Caption'),
                  if (captions.active)
                    Pill(captions.status == 'loading' ? tr('加载中', 'Loading') : tr('字幕运行中', 'Captions on')),
                ],
              ),
            ),
          ),
          const SizedBox(
            width: 138,
            height: 46,
            child: WindowCaption(brightness: Brightness.dark, backgroundColor: Colors.transparent),
          ),
        ],
      ),
    );
  }
}

class _Rail extends StatelessWidget {
  const _Rail({required this.index, required this.onSelect});

  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return SizedBox(
      width: 78,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _pages.length,
        separatorBuilder: (_, _) => const SizedBox(height: 2),
        itemBuilder: (context, i) {
          final selected = i == index;
          return HoverButton(
            onPressed: () => onSelect(i),
            builder: (context, states) {
              final hovered = states.contains(WidgetState.hovered);
              return Container(
                height: 56,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: selected
                      ? theme.resources.subtleFillColorSecondary
                      : hovered
                      ? theme.resources.subtleFillColorTertiary
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (selected)
                      Positioned(
                        left: 0,
                        top: 14,
                        bottom: 14,
                        child: Container(
                          width: 3,
                          decoration: BoxDecoration(color: theme.accentColor, borderRadius: BorderRadius.circular(2)),
                        ),
                      ),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(_pages[i].icon, size: 20, color: selected ? theme.accentColor.lightest : null),
                        const SizedBox(height: 4),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(_pages[i].label(), maxLines: 1, style: const TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
