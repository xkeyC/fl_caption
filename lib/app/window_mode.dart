import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart' as acrylic;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'settings.dart';

/// One window, two modes: the transparent always-on-top caption bar, and a
/// normal window for settings and the other pages (no second window).
enum WindowMode { overlay, console }

const _consoleSize = Size(1180, 780);
const _overlayDefault = Size(1100, 150);

class WindowModeController extends Notifier<WindowMode> {
  Rect? _consoleBounds;

  @override
  WindowMode build() => ref.read(initialSettingsProvider).startInOverlay ? WindowMode.overlay : WindowMode.console;

  /// Click-through overlay: mouse events pass to the windows below.
  bool clickThrough = false;

  Future<void> apply(WindowMode mode, {bool initial = false}) async {
    if (!initial && mode == state) return;
    final previous = state;
    if (!initial && previous == WindowMode.console) {
      _consoleBounds = await windowManager.getBounds();
    }
    if (!initial && previous == WindowMode.overlay) {
      await _saveOverlayBounds();
      await setClickThrough(false);
    }
    state = mode;
    if (mode == WindowMode.overlay) {
      await _toOverlay();
    } else {
      await _toConsole();
    }
  }

  Future<void> toggle() => apply(state == WindowMode.overlay ? WindowMode.console : WindowMode.overlay);

  Future<void> setClickThrough(bool value) async {
    clickThrough = value;
    await windowManager.setIgnoreMouseEvents(value, forward: true);
    ref.notifyListeners();
  }

  Future<void> _toOverlay() async {
    await windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: false);
    await windowManager.setAsFrameless();
    await windowManager.setResizable(true);
    await windowManager.setMinimumSize(const Size(420, 70));
    await windowManager.setAlwaysOnTop(true);
    await windowManager.setSkipTaskbar(false);
    await windowManager.setHasShadow(false);
    await windowManager.setBackgroundColor(Colors.transparent);
    if (Platform.isWindows) {
      await acrylic.Window.setEffect(effect: acrylic.WindowEffect.transparent);
    }
    final saved = ref.read(settingsProvider).overlayBounds;
    if (saved != null && saved.length == 4) {
      await windowManager.setBounds(Rect.fromLTWH(saved[0], saved[1], saved[2], saved[3]));
    } else {
      await windowManager.setSize(_overlayDefault);
      await windowManager.setAlignment(Alignment.bottomCenter);
    }
  }

  Future<void> _toConsole() async {
    await windowManager.setAlwaysOnTop(false);
    await windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: false);
    await windowManager.setHasShadow(true);
    await windowManager.setMinimumSize(const Size(900, 600));
    if (Platform.isWindows) {
      await acrylic.Window.setEffect(effect: acrylic.WindowEffect.disabled);
    }
    await windowManager.setBackgroundColor(const Color(0xFF14161A));
    final bounds = _consoleBounds;
    if (bounds != null) {
      await windowManager.setBounds(bounds);
    } else {
      await windowManager.setSize(_consoleSize);
      await windowManager.center();
    }
  }

  Future<void> _saveOverlayBounds() async {
    final b = await windowManager.getBounds();
    ref.read(settingsProvider.notifier).update((s) => s.copyWith(overlayBounds: [b.left, b.top, b.width, b.height]));
  }

  /// Remembers where the caption bar was moved to (called on move/resize).
  Future<void> overlayMoved() async {
    if (state == WindowMode.overlay) await _saveOverlayBounds();
  }
}

final windowModeProvider = NotifierProvider<WindowModeController, WindowMode>(WindowModeController.new);

/// Physical display scale of the window's screen (for crisp text sizes).
double get devicePixelRatio => PlatformDispatcher.instance.views.first.devicePixelRatio;
