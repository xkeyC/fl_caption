import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:fl_caption/common/settings_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show MethodCall;

class MultiWindowWindowUtil {
  static int mainWindowId = 0;

  // 记录当前是否是主窗口
  static bool isMainWindow = false;

  // 子窗口统一调用
  static Future windowMethodHandler(MethodCall call, int fromWindowId) async {
    switch (call.method) {
      case "main_window_id_broadcast":
        MultiWindowWindowUtil.mainWindowId = fromWindowId;
        debugPrint("Main window ID broadcast: $fromWindowId");
        break;
    }
    return null;
  }

  static Future<void> closeMineWindow() async {
    await DesktopMultiWindow.invokeMethod(mainWindowId, "close_mine_window");
  }

  static Future<AppSettingsData> getAppSettingsData() async {
    final result = await DesktopMultiWindow.invokeMethod(mainWindowId, "get_app_settings");
    return AppSettingsData.fromJson(Map<String, dynamic>.from(result as Map));
  }

  static Future<bool> setAppSettingsData(AppSettingsData settings) async {
    final result = await DesktopMultiWindow.invokeMethod(mainWindowId, "set_app_settings", settings.toJson());
    return result as bool;
  }
}
