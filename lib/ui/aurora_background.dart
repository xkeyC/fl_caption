import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/scheduler.dart';
import 'package:window_manager/window_manager.dart';

/// A slowly drifting blue-green aurora behind the console window, drawn by
/// hand (no platform acrylic). Adapted from StarCitizenToolBox's nebula
/// background: rendered at a fraction of the window resolution and
/// stretched, repainted at most 30 times a second, and paused while the
/// window is unfocused or minimised. Moving the window shifts the aurora
/// against it (parallax), as if it hung behind the screen.
class AuroraBackground extends StatefulWidget {
  const AuroraBackground({super.key, this.animated = true});

  final bool animated;

  @override
  State<AuroraBackground> createState() => _AuroraBackgroundState();
}

class _AuroraBackgroundState extends State<AuroraBackground> with SingleTickerProviderStateMixin, WindowListener {
  static const _frameInterval = Duration(milliseconds: 33);

  final _time = ValueNotifier<double>(0);

  /// The window's position on screen, for the parallax shift.
  final _window = ValueNotifier<Offset>(Offset.zero);
  late final Ticker _ticker = createTicker(_onTick);
  Duration _lastFrame = Duration.zero;
  bool _minimized = false;
  bool _focused = true;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _syncPosition();
    _update();
  }

  Future<void> _syncPosition() async {
    try {
      final position = await windowManager.getPosition();
      if (mounted) _window.value = position;
    } catch (_) {
      // Only a nicety: keep the last offset.
    }
  }

  @override
  void didUpdateWidget(AuroraBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    _update();
  }

  void _update() {
    final run = widget.animated && !_minimized && _focused;
    if (run && !_ticker.isActive) {
      _lastFrame = Duration.zero;
      _ticker.start();
    } else if (!run && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _onTick(Duration elapsed) {
    if (elapsed - _lastFrame < _frameInterval) return;
    _time.value += (elapsed - _lastFrame).inMicroseconds / 1e6;
    _lastFrame = elapsed;
  }

  @override
  void onWindowFocus() {
    _focused = true;
    _update();
  }

  @override
  void onWindowBlur() {
    _focused = false;
    _update();
  }

  @override
  void onWindowMove() => _syncPosition();

  @override
  void onWindowMoved() => _syncPosition();

  @override
  void onWindowMinimize() {
    _minimized = true;
    _update();
  }

  @override
  void onWindowRestore() {
    _minimized = false;
    _update();
    _syncPosition();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _ticker.dispose();
    _time.dispose();
    _window.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(painter: _AuroraPainter(_time, _window), child: const SizedBox.expand()),
    );
  }
}

class _AuroraPainter extends CustomPainter {
  _AuroraPainter(this.time, this.window) : super(repaint: Listenable.merge([time, window]));

  final ValueNotifier<double> time;
  final ValueNotifier<Offset> window;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final width = math.max(1, (size.width / _downscale).ceil());
    final height = math.max(1, (size.height / _downscale).ceil());
    final recorder = ui.PictureRecorder();
    final small = Canvas(recorder)..scale(width / size.width, height / size.height);
    _paintAurora(small, Offset.zero & size, time.value, -window.value * _parallax);
    final picture = recorder.endRecording();
    final image = picture.toImageSync(width, height);
    picture.dispose();
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.low,
    );
    image.dispose();
  }

  @override
  bool shouldRepaint(_AuroraPainter oldDelegate) => false;
}

/// The aurora has no fine detail: rendered at 1/6 of the resolution.
const _downscale = 6.0;

const _base = Color(0xff0a1a24);

/// How far the aurora moves against the window: 1 would pin it to the
/// screen; less reads as a more distant layer.
const _parallax = 0.35;

class _Band {
  const _Band({
    required this.anchor,
    required this.radius,
    required this.stretch,
    required this.tilt,
    required this.color,
    required this.drift,
    required this.speed,
    required this.phase,
  });

  /// Rest position as a fraction of the view.
  final Offset anchor;

  /// Radius as a fraction of the longer side, before [stretch].
  final double radius;

  /// Horizontal stretch: > 1 draws a ribbon rather than a cloud.
  final double stretch;

  /// Rotation in radians.
  final double tilt;
  final Color color;

  /// Drift amplitude in logical pixels.
  final Offset drift;

  /// Radians per second.
  final double speed;
  final double phase;
}

const _bands = [
  // Teal curtain across the top.
  _Band(
    anchor: Offset(0.3, 0.12),
    radius: 0.34,
    stretch: 2.6,
    tilt: -0.18,
    color: Color(0xcc1fd1bc),
    drift: Offset(200, 60),
    speed: 0.11,
    phase: 0,
  ),
  // Green glow, lower left.
  _Band(
    anchor: Offset(0.12, 0.78),
    radius: 0.3,
    stretch: 2.0,
    tilt: 0.25,
    color: Color(0xa630e098),
    drift: Offset(160, 90),
    speed: 0.09,
    phase: 1.7,
  ),
  // Cyan ribbon through the middle.
  _Band(
    anchor: Offset(0.72, 0.42),
    radius: 0.3,
    stretch: 3.0,
    tilt: -0.32,
    color: Color(0xb32aaee6),
    drift: Offset(220, 110),
    speed: 0.13,
    phase: 3.3,
  ),
  // Deep blue body, right and bottom.
  _Band(
    anchor: Offset(0.85, 0.95),
    radius: 0.5,
    stretch: 1.4,
    tilt: 0.1,
    color: Color(0xb32450b4),
    drift: Offset(140, 120),
    speed: 0.07,
    phase: 4.6,
  ),
  // A faint violet edge for depth.
  _Band(
    anchor: Offset(0.98, 0.08),
    radius: 0.24,
    stretch: 1.8,
    tilt: 0.4,
    color: Color(0x806a5ed6),
    drift: Offset(120, 70),
    speed: 0.1,
    phase: 2.4,
  ),
];

void _paintAurora(Canvas canvas, Rect rect, double t, Offset shift) {
  canvas.drawRect(rect, Paint()..color = _base);
  final size = rect.size;
  final longSide = math.max(size.width, size.height);
  for (final band in _bands) {
    // Breathing radius and a slow sway of the ribbon's angle.
    final radius = band.radius * longSide * (1 + 0.1 * math.sin(t * band.speed * 1.4 + band.phase * 2));
    // The ribbon is wider than its radius: wrap with its stretched extent.
    final reach = radius * band.stretch;
    final center = Offset(
      _wrap(
        band.anchor.dx * size.width + band.drift.dx * math.sin(t * band.speed + band.phase) + shift.dx,
        size.width,
        reach,
      ),
      _wrap(
        band.anchor.dy * size.height + band.drift.dy * math.cos(t * band.speed * 0.8 + band.phase) + shift.dy,
        size.height,
        reach,
      ),
    );
    final angle = band.tilt + 0.12 * math.sin(t * band.speed * 0.6 + band.phase);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);
    canvas.scale(band.stretch, 1);
    final paint = Paint()
      ..shader = ui.Gradient.radial(Offset.zero, radius, [band.color, band.color.withValues(alpha: 0)]);
    canvas.drawCircle(Offset.zero, radius, paint);
    canvas.restore();
  }
  // Darken the bottom a little so text stays readable.
  canvas.drawRect(
    rect,
    Paint()
      ..shader = ui.Gradient.linear(rect.topCenter, rect.bottomCenter, [
        const Color(0x00000000),
        const Color(0x33000000),
      ]),
  );
}

/// Wraps a band's centre into a period wider than the view by its reach on
/// both sides, so a band leaving one edge comes back in at the other while
/// out of sight, without popping.
double _wrap(double value, double extent, double reach) {
  final period = extent + reach * 2;
  return ((value + reach) % period + period) % period - reach;
}
