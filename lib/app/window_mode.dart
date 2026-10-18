import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart' as acrylic;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'settings.dart';

const _overlayDefault = Size(1100, 220);

/// The main window is the caption bar: frameless, transparent, always on
/// top; optionally click-through (unlocked from the tray or the hotkey).
class OverlayController extends Notifier<bool> {
  /// State: whether mouse clicks pass through the bar.
  @override
  bool build() => false;

  bool get clickThrough => state;

  Future<void> setUp() async {
    await windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: false);
    await windowManager.setAsFrameless();
    await windowManager.setResizable(true);
    await windowManager.setMinimumSize(const Size(420, 90));
    await windowManager.setAlwaysOnTop(true);
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

  Future<void> setClickThrough(bool value) async {
    await windowManager.setIgnoreMouseEvents(value, forward: true);
    state = value;
  }

  /// Remembers where the bar was moved or resized to.
  Future<void> saveBounds() async {
    final b = await windowManager.getBounds();
    ref.read(settingsProvider.notifier).update((s) => s.copyWith(overlayBounds: [b.left, b.top, b.width, b.height]));
  }
}

final overlayProvider = NotifierProvider<OverlayController, bool>(OverlayController.new);
