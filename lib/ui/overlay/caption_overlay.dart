import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../app/captions.dart';
import '../../app/i18n.dart';
import '../../app/settings.dart';
import '../../app/window_mode.dart';
import '../theme.dart';

/// The transparent caption bar: the current line growing as it is spoken,
/// earlier lines above it, and a toolbar while the mouse is over it.
class CaptionOverlay extends HookConsumerWidget {
  const CaptionOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final captions = ref.watch(captionProvider);
    final hovering = useState(false);
    final color = Color(s.textColor);

    final lines = captions.lines;
    final current = lines.isEmpty ? null : lines.last;
    final history = lines.length < 2
        ? const <CaptionLine>[]
        : lines.sublist((lines.length - 1 - s.historyLines).clamp(0, lines.length - 1), lines.length - 1);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: DragToResizeArea(
        resizeEdgeSize: 6,
        child: MouseRegion(
          onEnter: (_) => hovering.value = true,
          onExit: (_) => hovering.value = false,
          child: DragToMoveArea(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: s.backgroundOpacity),
                borderRadius: BorderRadius.circular(14),
                border: hovering.value ? Border.all(color: Colors.white24) : null,
              ),
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        for (final line in history)
                          Opacity(opacity: 0.55, child: _LineView(line: line, settings: s, color: color, current: false)),
                        if (current != null)
                          _LineView(line: current, settings: s, color: color, current: true)
                        else
                          _StatusText(state: captions),
                      ],
                    ),
                  ),
                  if (hovering.value) const Positioned(top: 0, right: 0, child: _Toolbar()),
                  if (s.showStatus && hovering.value) Positioned(left: 0, top: 0, child: _MiniStatus(state: captions)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LineView extends StatelessWidget {
  const _LineView({required this.line, required this.settings, required this.color, required this.current});

  final CaptionLine line;
  final AppSettings settings;
  final Color color;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final s = settings;
    final showTranslation = s.translationEnabled && s.captionLines != CaptionLines.sourceOnly && !line.sameLanguage;
    final showSource = s.captionLines != CaptionLines.translationOnly || !showTranslation || line.translation.isEmpty;
    final sourceStyle = TextStyle(
      fontSize: showTranslation ? s.sourceFontSize : s.translationFontSize,
      color: color.withValues(alpha: showTranslation ? 0.8 : 1),
      height: 1.3,
      shadows: const [Shadow(blurRadius: 4, color: Colors.black87)],
    );
    final translationStyle = TextStyle(
      fontSize: s.translationFontSize,
      color: color,
      height: 1.3,
      fontWeight: FontWeight.w500,
      shadows: const [Shadow(blurRadius: 4, color: Colors.black87)],
    );

    final source = showSource
        ? _TailText(
            stable: line.isFinal ? line.source : line.source.substring(0, line.stableChars.clamp(0, line.source.length)),
            tail: line.isFinal ? '' : line.source.substring(line.stableChars.clamp(0, line.source.length)),
            growing: !line.isFinal,
            style: sourceStyle,
          )
        : null;
    final translationText = line.translation;
    final translation = showTranslation && translationText.isNotEmpty
        ? _TailText(
            stable: line.translationDone && !line.translationIsPartial ? translationText : '',
            tail: line.translationDone && !line.translationIsPartial ? '' : translationText,
            growing: !line.translationDone || line.translationIsPartial,
            style: translationStyle,
          )
        : null;
    final children = s.translationFirst ? [translation, source] : [source, translation];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [for (final c in children) ?c],
      ),
    );
  }
}

/// One line of text: `stable` solid, `tail` faded; when too long for one
/// line, the start is cut (the newest words stay visible).
class _TailText extends StatelessWidget {
  const _TailText({required this.stable, required this.tail, required this.growing, required this.style});

  final String stable;
  final String tail;
  final bool growing;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final faded = style.copyWith(color: style.color?.withValues(alpha: (style.color?.a ?? 1) * 0.55));
      final ellipsis = growing ? '…' : '';
      var cut = 0;
      final full = stable + tail;
      bool fits(int from) {
        final painter = TextPainter(
          text: TextSpan(text: '${from > 0 ? '…' : ''}${full.substring(from)}$ellipsis', style: style),
          maxLines: 1,
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: constraints.maxWidth);
        return !painter.didExceedMaxLines;
      }

      if (!fits(0)) {
        var lo = 1, hi = full.length;
        while (lo < hi) {
          final mid = (lo + hi) ~/ 2;
          if (fits(mid)) {
            hi = mid;
          } else {
            lo = mid + 1;
          }
        }
        cut = lo;
      }
      final stableShown = cut < stable.length ? stable.substring(cut) : '';
      final tailShown = cut <= stable.length ? tail : tail.substring(cut - stable.length);
      return Text.rich(
        TextSpan(children: [
          if (cut > 0) TextSpan(text: '…', style: faded),
          TextSpan(text: stableShown, style: style),
          TextSpan(text: tailShown, style: faded),
          if (growing) TextSpan(text: ellipsis, style: faded),
        ]),
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.clip,
        textAlign: TextAlign.center,
      );
    });
  }
}

class _StatusText extends StatelessWidget {
  const _StatusText({required this.state});

  final CaptionState state;

  @override
  Widget build(BuildContext context) {
    final text = switch (state.status) {
      CaptionStatus.idle => tr('字幕已停止 — 悬停后点击 ▶ 开始', 'Captions stopped — hover and press ▶'),
      CaptionStatus.loading => state.message == 'translator'
          ? tr('正在加载翻译模型…', 'Loading the translation model…')
          : tr('正在加载语音模型…', 'Loading the speech model…'),
      CaptionStatus.running => tr('正在聆听…', 'Listening…'),
      CaptionStatus.failed => '${tr('出错了', 'Error')}: ${state.message}',
    };
    return Text(
      text,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: state.status == CaptionStatus.failed ? Colors.redAccent.shade100 : Colors.white70,
        fontSize: 15,
      ),
    );
  }
}

class _MiniStatus extends StatelessWidget {
  const _MiniStatus({required this.state});

  final CaptionState state;

  @override
  Widget build(BuildContext context) {
    final level = (state.level * 8).clamp(0.0, 1.0);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(2)),
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: level,
            child: Container(decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(2))),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          state.provider.isEmpty ? '' : state.provider.toUpperCase(),
          style: const TextStyle(fontSize: 11, color: Colors.white54),
        ),
      ],
    );
  }
}

class _Toolbar extends ConsumerWidget {
  const _Toolbar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final captions = ref.watch(captionProvider);
    final window = ref.watch(windowModeProvider.notifier);
    ref.watch(windowModeProvider);
    Widget button(IconData icon, String tip, VoidCallback onPressed) => IconButton(
          icon: Icon(icon, size: 18, color: Colors.white70),
          tooltip: tip,
          visualDensity: VisualDensity.compact,
          onPressed: onPressed,
        );
    return Container(
      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(10)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          button(
            captions.active ? Icons.pause_rounded : Icons.play_arrow_rounded,
            captions.active ? tr('停止字幕', 'Stop captions') : tr('开始字幕', 'Start captions'),
            () => ref.read(captionProvider.notifier).toggle(),
          ),
          button(Icons.lock_outline_rounded, tr('锁定（鼠标穿透，可在托盘解锁）', 'Lock (click-through; unlock from the tray)'),
              () => window.setClickThrough(true)),
          button(Icons.tune_rounded, tr('设置', 'Settings'), () => window.apply(WindowMode.console)),
        ],
      ),
    );
  }
}
