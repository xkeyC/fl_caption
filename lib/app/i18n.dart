import 'dart:ui';

/// The UI language: Chinese or English, both strings written where they are
/// used (`tr('中文', 'English')`).
class I18n {
  static bool zh = true;

  /// `system`, `zh` or `en`.
  static void use(String setting) {
    zh = switch (setting) {
      'zh' => true,
      'en' => false,
      _ => PlatformDispatcher.instance.locale.languageCode == 'zh',
    };
  }
}

String tr(String zh, String en) => I18n.zh ? zh : en;
