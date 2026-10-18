import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

/// The windows: the caption bar is the main window (it runs the captions);
/// settings open in a sub window with its own engine, which talks to the
/// main window over [mainChannel] and hears back on [settingsChannel].
class WindowTypes {
  static const main = 'main';
  static const settings = 'settings';
}

/// Registered by the main window; the settings window invokes it.
const mainChannel = WindowMethodChannel('fl_caption/main', mode: ChannelMode.unidirectional);

/// Registered by the settings window; the main window pushes to it.
const settingsChannel = WindowMethodChannel('fl_caption/settings', mode: ChannelMode.unidirectional);

String windowTypeOf(String arguments) {
  if (arguments.isEmpty) return WindowTypes.main;
  try {
    return (jsonDecode(arguments) as Map)['window_type'] as String? ?? WindowTypes.main;
  } catch (_) {
    return WindowTypes.main;
  }
}

/// Opens the settings window, or brings the open one to the front.
Future<void> openSettingsWindow({int page = 0}) async {
  for (final controller in await WindowController.getAll()) {
    if (windowTypeOf(controller.arguments) == WindowTypes.settings) {
      await controller.invokeMethod('window_show');
      try {
        await settingsChannel.invokeMethod('select_page', page);
      } catch (_) {}
      return;
    }
  }
  final controller = await WindowController.create(
    WindowConfiguration(
      hiddenAtLaunch: true,
      arguments: jsonEncode({'window_type': WindowTypes.settings, 'page': page}),
    ),
  );
  await controller.show();
}

/// Window control the main window may ask of a sub window (its own
/// window_manager), as StarCitizenToolBox does.
extension SubWindowControl on WindowController {
  Future<void> handleWindowCalls() async {
    await windowManager.ensureInitialized();
    await setWindowMethodHandler((call) async {
      switch (call.method) {
        case 'window_show':
          await windowManager.show();
          return windowManager.focus();
        case 'window_close':
          return windowManager.close();
        default:
          throw MissingPluginException('Not implemented: ${call.method}');
      }
    });
  }
}
