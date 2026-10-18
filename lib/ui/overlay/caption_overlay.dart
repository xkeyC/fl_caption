import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../app/captions.dart';
import '../../app/i18n.dart';
import '../../app/models.dart';
import '../../app/settings.dart';
import '../../app/window_mode.dart';
import '../../app/windows.dart';
import '../../main.dart' show quitApp;

/// The transparent caption bar: earlier lines and the current one in fixed
/// rows, text anchored left (it only grows at its end), the latency line at
/// the bottom left and a toolbar while the mouse is over it.
class CaptionOverlay extends HookConsumerWidget {
  const CaptionOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final captions = ref.watch(captionProvider);
    final hovering = useState(false);
    final color = Color(s.textColor);
    final runtime = ref.watch(runtimeInfoProvider);

    final lines = captions.lines;
    final current = lines.isEmpty ? null : lines.last;
    final history = lines.length < 2
        ? const <CaptionLine>[]
        : lines.sublist((lines.length - 1 - s.historyLines).clamp(0, lines.length - 1), lines.length - 1);

    return DragToResizeArea(
      resizeEdgeSize: 6,
      child: MouseRegion(
        onEnter: (_) => hovering.value = true,
        onExit: (_) => hovering.value = false,
        child: DragToMoveArea(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: s.backgroundOpacity),
              borderRadius: BorderRadius.circular(12),
              // Always 1 px: hovering only colours it, so the content never shifts.
              border: Border.all(color: Colors.white.withValues(alpha: hovering.value ? 0.18 : 0)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
            child: Stack(
              children: [
                Positioned.fill(
                  bottom: s.showStatus ? 18 : 0,
                  child: ClipRect(
                    child: OverflowBox(
                      alignment: Alignment.topLeft,
                      maxHeight: double.infinity,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // The history rows are always there (empty at
                          // first), so the current line never moves.
                          for (var i = 0; i < s.historyLines - history.length; i++)
                            _LineView(line: const CaptionLine(id: -1), settings: s, color: color, current: false),
                          for (final line in history)
                            Opacity(
                              opacity: 0.55,
                              child: _LineView(line: line, settings: s, color: color, current: false),
                            ),
                          if (runtime.error != null)
                            _RuntimeError(error: runtime.error!, logFile: runtime.logFile)
                          else if (current != null)
                            _LineView(line: current, settings: s, color: color, current: true)
                          else
                            _StatusText(state: captions),
                        ],
                      ),
                    ),
                  ),
                ),
                if (s.showStatus)
                  Positioned(
                    left: 0,
                    bottom: 0,
                    child: _Latency(state: captions, settings: s),
                  ),
                if (hovering.value) const Positioned(top: 0, right: 0, child: _Toolbar()),
              ],
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
    final showSource = s.captionLines != CaptionLines.translationOnly || !showTranslation;
    final sourceStyle = TextStyle(
      fontSize: showTranslation ? s.sourceFontSize : s.translationFontSize,
      color: color.withValues(alpha: showTranslation ? 0.8 : 1),
      height: 1.3,
      shadows: const [Shadow(blurRadius: 4, color: Color(0xDD000000))],
    );
    final translationStyle = TextStyle(
      fontSize: s.translationFontSize,
      color: color,
      height: 1.3,
      fontWeight: FontWeight.w500,
      shadows: const [Shadow(blurRadius: 4, color: Color(0xDD000000))],
    );
    final lines = current ? 2 : 1;
    final source = showSource ? _AnchoredText(text: line.source, style: sourceStyle, lines: lines) : null;
    final translation = showTranslation
        ? _AnchoredText(text: line.translation, style: translationStyle, lines: lines)
        : null;
    final children = s.translationFirst ? [translation, source] : [source, translation];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [for (final c in children) ?c],
      ),
    );
  }
}

/// Text in a fixed box of `lines` lines, anchored at its top-left corner:
/// text that grows only extends at its end, nothing moves sideways or
/// scrolls. When it outgrows the box, the box shows the next page (from
/// the start of its last line) at once, without animation.
class _AnchoredText extends StatelessWidget {
  const _AnchoredText({required this.text, required this.style, required this.lines});

  final String text;
  final TextStyle style;
  final int lines;

  @override
  Widget build(BuildContext context) {
    final lineHeight = (style.fontSize ?? 16) * (style.height ?? 1.3);
    return SizedBox(
      height: lineHeight * lines,
      child: LayoutBuilder(
        builder: (context, constraints) {
          var shown = text;
          final painter = TextPainter(
            text: TextSpan(text: text, style: style),
            textDirection: TextDirection.ltr,
          )..layout(maxWidth: constraints.maxWidth);
          final metrics = painter.computeLineMetrics();
          if (metrics.length > lines) {
            // The page holding the last line: whole pages of `lines` lines.
            final page = (metrics.length - 1) ~/ lines * lines;
            final y = metrics[page].baseline - metrics[page].ascent + 1;
            final start = painter.getPositionForOffset(Offset(0, y)).offset;
            shown = text.substring(start.clamp(0, text.length));
          }
          painter.dispose();
          return Text(shown, style: style, textAlign: TextAlign.left, maxLines: lines, overflow: TextOverflow.clip);
        },
      ),
    );
  }
}

/// ONNX Runtime could not be loaded: nothing can run, so the bar says why.
class _RuntimeError extends StatelessWidget {
  const _RuntimeError({required this.error, required this.logFile});

  final String error;
  final String logFile;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          tr('ONNX Runtime 初始化失败，无法识别字幕', 'ONNX Runtime failed to load: captions cannot run'),
          style: TextStyle(color: Colors.red.lightest, fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          error,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white, fontSize: 13.5),
        ),
        const SizedBox(height: 4),
        Text(
          tr(
            '请确认 runtime/ort 或 runtime/ort-cpu 已解压到程序目录。日志：$logFile',
            'Make sure runtime/ort or runtime/ort-cpu is unpacked beside the program. Log: $logFile',
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Color(0x99FFFFFF), fontSize: 12),
        ),
      ],
    );
  }
}

class _StatusText extends StatelessWidget {
  const _StatusText({required this.state});

  final CaptionState state;

  @override
  Widget build(BuildContext context) {
    final text = switch (state.status) {
      CaptionStatus.idle => tr('字幕已停止 — 悬停后点击 ▶ 开始', 'Captions stopped — hover and press ▶'),
      CaptionStatus.loading =>
        state.message == 'translator'
            ? tr('正在加载翻译模型…', 'Loading the translation model…')
            : tr('正在加载语音模型…', 'Loading the speech model…'),
      CaptionStatus.running => tr('正在聆听…', 'Listening…'),
      CaptionStatus.failed => '${tr('出错了', 'Error')}: ${state.message}',
    };
    return Text(
      text,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(color: state.status == CaptionStatus.failed ? Colors.red.lightest : Colors.white, fontSize: 15),
    );
  }
}

/// ASR latency, translation latency and how much of the longest line the
/// line being spoken has used (the audio buffer), as the old bar showed.
class _Latency extends StatelessWidget {
  const _Latency({required this.state, required this.settings});

  final CaptionState state;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final lines = state.lines;
    final current = lines.isEmpty ? null : lines.last;
    final lastTranslated = lines.lastWhere((l) => l.translationMs > 0, orElse: () => const CaptionLine(id: -1));
    final buffer = current == null || current.isFinal ? 0.0 : (current.endMs - current.startMs) / 1000;
    final max = settings.maxSegmentMs / 1000;
    final bufferColor = buffer > max * 0.85
        ? Colors.red.lighter
        : buffer > max * 0.6
        ? Colors.yellow
        : Colors.white.withValues(alpha: 0.55);
    const style = TextStyle(fontSize: 11.5, color: Color(0x8CFFFFFF));
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('ASR ${current?.asrMs ?? 0} ms', style: style),
        const Text('  ·  ', style: style),
        if (settings.translationEnabled) ...[
          Text('${tr('翻译', 'Translate')} ${lastTranslated.translationMs} ms', style: style),
          const Text('  ·  ', style: style),
        ],
        Text('${tr('缓冲', 'Buffer')} ', style: style),
        Text('${buffer.toStringAsFixed(1)} / ${max.toStringAsFixed(0)} s', style: style.copyWith(color: bufferColor)),
        if (state.provider.isNotEmpty) Text('  ·  ${state.provider.toUpperCase()}', style: style),
      ],
    );
  }
}

class _Toolbar extends ConsumerWidget {
  const _Toolbar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final captions = ref.watch(captionProvider);
    final controller = ref.read(captionProvider.notifier);
    final overlay = ref.read(overlayProvider.notifier);
    Widget button(IconData icon, String tip, VoidCallback onPressed) => Tooltip(
      message: tip,
      child: IconButton(
        icon: Icon(icon, size: 16, color: Colors.white),
        onPressed: onPressed,
      ),
    );
    return Container(
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          button(
            captions.active ? FluentIcons.pause : FluentIcons.play,
            captions.active ? tr('停止字幕', 'Stop captions') : tr('开始字幕', 'Start captions'),
            controller.toggle,
          ),
          button(
            FluentIcons.lock,
            tr('锁定（鼠标穿透，可在托盘解锁）', 'Lock (click-through; unlock from the tray)'),
            () => overlay.setClickThrough(true),
          ),
          button(
            FluentIcons.broom,
            tr('清理上下文（清空字幕记录与翻译参考的前文）', "Clear the context (captions kept and the translator's earlier lines)"),
            controller.clearContext,
          ),
          button(
            FluentIcons.download,
            tr(
              '导出上下文（最近 ${controller.history.length} 条，含时间）',
              'Export the context (last ${controller.history.length} lines with times)',
            ),
            controller.exportContext,
          ),
          button(FluentIcons.settings, tr('设置', 'Settings'), () => openSettingsWindow()),
          button(FluentIcons.chrome_close, tr('退出', 'Quit'), () => quitApp(controller)),
        ],
      ),
    );
  }
}
