/// Language data for Whisper model
class WhisperLanguage {
  /// ISO language code
  final String code;

  /// English name of the language
  final String name;

  /// Display name (same as English name)
  final String displayName;

  /// Display name in the native language
  final String displayLocaleName;

  const WhisperLanguage({
    required this.code,
    required this.name,
    required this.displayName,
    required this.displayLocaleName,
  });
}

/// 语言映射表，包含 Whisper 支持的所有语言
/// Language mapping containing all languages supported by Whisper

const Map<String, WhisperLanguage> whisperLanguages = {
  "en": WhisperLanguage(code: "en", name: "english", displayName: "English", displayLocaleName: "English"),
  "zh": WhisperLanguage(code: "zh", name: "chinese", displayName: "Chinese", displayLocaleName: "中文"),
  "de": WhisperLanguage(code: "de", name: "german", displayName: "German", displayLocaleName: "Deutsch"),
  "es": WhisperLanguage(code: "es", name: "spanish", displayName: "Spanish", displayLocaleName: "Español"),
  "ru": WhisperLanguage(code: "ru", name: "russian", displayName: "Russian", displayLocaleName: "Русский"),
  "ko": WhisperLanguage(code: "ko", name: "korean", displayName: "Korean", displayLocaleName: "한국어"),
  "fr": WhisperLanguage(code: "fr", name: "french", displayName: "French", displayLocaleName: "Français"),
  "ja": WhisperLanguage(code: "ja", name: "japanese", displayName: "Japanese", displayLocaleName: "日本語"),
  "pt": WhisperLanguage(code: "pt", name: "portuguese", displayName: "Portuguese", displayLocaleName: "Português"),
  "tr": WhisperLanguage(code: "tr", name: "turkish", displayName: "Turkish", displayLocaleName: "Türkçe"),
  "pl": WhisperLanguage(code: "pl", name: "polish", displayName: "Polish", displayLocaleName: "Polski"),
  "ca": WhisperLanguage(code: "ca", name: "catalan", displayName: "Catalan", displayLocaleName: "Català"),
  "nl": WhisperLanguage(code: "nl", name: "dutch", displayName: "Dutch", displayLocaleName: "Nederlands"),
  "ar": WhisperLanguage(code: "ar", name: "arabic", displayName: "Arabic", displayLocaleName: "العربية"),
  "sv": WhisperLanguage(code: "sv", name: "swedish", displayName: "Swedish", displayLocaleName: "Svenska"),
  "it": WhisperLanguage(code: "it", name: "italian", displayName: "Italian", displayLocaleName: "Italiano"),
  "id": WhisperLanguage(
    code: "id",
    name: "indonesian",
    displayName: "Indonesian",
    displayLocaleName: "Bahasa Indonesia",
  ),
  "hi": WhisperLanguage(code: "hi", name: "hindi", displayName: "Hindi", displayLocaleName: "हिन्दी"),
  "fi": WhisperLanguage(code: "fi", name: "finnish", displayName: "Finnish", displayLocaleName: "Suomi"),
  "vi": WhisperLanguage(code: "vi", name: "vietnamese", displayName: "Vietnamese", displayLocaleName: "Tiếng Việt"),
  "he": WhisperLanguage(code: "he", name: "hebrew", displayName: "Hebrew", displayLocaleName: "עברית"),
  "uk": WhisperLanguage(code: "uk", name: "ukrainian", displayName: "Ukrainian", displayLocaleName: "Українська"),
  "el": WhisperLanguage(code: "el", name: "greek", displayName: "Greek", displayLocaleName: "Ελληνικά"),
  "ms": WhisperLanguage(code: "ms", name: "malay", displayName: "Malay", displayLocaleName: "Bahasa Melayu"),
  "cs": WhisperLanguage(code: "cs", name: "czech", displayName: "Czech", displayLocaleName: "Čeština"),
  "ro": WhisperLanguage(code: "ro", name: "romanian", displayName: "Romanian", displayLocaleName: "Română"),
  "da": WhisperLanguage(code: "da", name: "danish", displayName: "Danish", displayLocaleName: "Dansk"),
  "hu": WhisperLanguage(code: "hu", name: "hungarian", displayName: "Hungarian", displayLocaleName: "Magyar"),
  "ta": WhisperLanguage(code: "ta", name: "tamil", displayName: "Tamil", displayLocaleName: "தமிழ்"),
  "no": WhisperLanguage(code: "no", name: "norwegian", displayName: "Norwegian", displayLocaleName: "Norsk"),
  "th": WhisperLanguage(code: "th", name: "thai", displayName: "Thai", displayLocaleName: "ไทย"),
  "ur": WhisperLanguage(code: "ur", name: "urdu", displayName: "Urdu", displayLocaleName: "اردو"),
  "hr": WhisperLanguage(code: "hr", name: "croatian", displayName: "Croatian", displayLocaleName: "Hrvatski"),
  "bg": WhisperLanguage(code: "bg", name: "bulgarian", displayName: "Bulgarian", displayLocaleName: "Български"),
  "lt": WhisperLanguage(code: "lt", name: "lithuanian", displayName: "Lithuanian", displayLocaleName: "Lietuvių"),
  "la": WhisperLanguage(code: "la", name: "latin", displayName: "Latin", displayLocaleName: "Latina"),
  "mi": WhisperLanguage(code: "mi", name: "maori", displayName: "Maori", displayLocaleName: "Māori"),
  "ml": WhisperLanguage(code: "ml", name: "malayalam", displayName: "Malayalam", displayLocaleName: "മലയാളം"),
  "cy": WhisperLanguage(code: "cy", name: "welsh", displayName: "Welsh", displayLocaleName: "Cymraeg"),
  "sk": WhisperLanguage(code: "sk", name: "slovak", displayName: "Slovak", displayLocaleName: "Slovenčina"),
  "te": WhisperLanguage(code: "te", name: "telugu", displayName: "Telugu", displayLocaleName: "తెలుగు"),
  "fa": WhisperLanguage(code: "fa", name: "persian", displayName: "Persian", displayLocaleName: "فارسی"),
  "lv": WhisperLanguage(code: "lv", name: "latvian", displayName: "Latvian", displayLocaleName: "Latviešu"),
  "bn": WhisperLanguage(code: "bn", name: "bengali", displayName: "Bengali", displayLocaleName: "বাংলা"),
  "sr": WhisperLanguage(code: "sr", name: "serbian", displayName: "Serbian", displayLocaleName: "Српски"),
  "az": WhisperLanguage(code: "az", name: "azerbaijani", displayName: "Azerbaijani", displayLocaleName: "Azərbaycan"),
  "sl": WhisperLanguage(code: "sl", name: "slovenian", displayName: "Slovenian", displayLocaleName: "Slovenščina"),
  "kn": WhisperLanguage(code: "kn", name: "kannada", displayName: "Kannada", displayLocaleName: "ಕನ್ನಡ"),
  "et": WhisperLanguage(code: "et", name: "estonian", displayName: "Estonian", displayLocaleName: "Eesti"),
  "mk": WhisperLanguage(code: "mk", name: "macedonian", displayName: "Macedonian", displayLocaleName: "Македонски"),
  "br": WhisperLanguage(code: "br", name: "breton", displayName: "Breton", displayLocaleName: "Brezhoneg"),
  "eu": WhisperLanguage(code: "eu", name: "basque", displayName: "Basque", displayLocaleName: "Euskara"),
  "is": WhisperLanguage(code: "is", name: "icelandic", displayName: "Icelandic", displayLocaleName: "Íslenska"),
  "hy": WhisperLanguage(code: "hy", name: "armenian", displayName: "Armenian", displayLocaleName: "Հայերեն"),
  "ne": WhisperLanguage(code: "ne", name: "nepali", displayName: "Nepali", displayLocaleName: "नेपाली"),
  "mn": WhisperLanguage(code: "mn", name: "mongolian", displayName: "Mongolian", displayLocaleName: "Монгол"),
  "bs": WhisperLanguage(code: "bs", name: "bosnian", displayName: "Bosnian", displayLocaleName: "Bosanski"),
  "kk": WhisperLanguage(code: "kk", name: "kazakh", displayName: "Kazakh", displayLocaleName: "Қазақ"),
  "sq": WhisperLanguage(code: "sq", name: "albanian", displayName: "Albanian", displayLocaleName: "Shqip"),
  "sw": WhisperLanguage(code: "sw", name: "swahili", displayName: "Swahili", displayLocaleName: "Kiswahili"),
  "gl": WhisperLanguage(code: "gl", name: "galician", displayName: "Galician", displayLocaleName: "Galego"),
  "mr": WhisperLanguage(code: "mr", name: "marathi", displayName: "Marathi", displayLocaleName: "मराठी"),
  "pa": WhisperLanguage(code: "pa", name: "punjabi", displayName: "Punjabi", displayLocaleName: "ਪੰਜਾਬੀ"),
  "si": WhisperLanguage(code: "si", name: "sinhala", displayName: "Sinhala", displayLocaleName: "සිංහල"),
  "km": WhisperLanguage(code: "km", name: "khmer", displayName: "Khmer", displayLocaleName: "ខ្មែរ"),
  "sn": WhisperLanguage(code: "sn", name: "shona", displayName: "Shona", displayLocaleName: "Shona"),
  "yo": WhisperLanguage(code: "yo", name: "yoruba", displayName: "Yoruba", displayLocaleName: "Yorùbá"),
  "so": WhisperLanguage(code: "so", name: "somali", displayName: "Somali", displayLocaleName: "Soomaali"),
  "af": WhisperLanguage(code: "af", name: "afrikaans", displayName: "Afrikaans", displayLocaleName: "Afrikaans"),
  "oc": WhisperLanguage(code: "oc", name: "occitan", displayName: "Occitan", displayLocaleName: "Occitan"),
  "ka": WhisperLanguage(code: "ka", name: "georgian", displayName: "Georgian", displayLocaleName: "ქართული"),
  "be": WhisperLanguage(code: "be", name: "belarusian", displayName: "Belarusian", displayLocaleName: "Беларуская"),
  "tg": WhisperLanguage(code: "tg", name: "tajik", displayName: "Tajik", displayLocaleName: "Тоҷикӣ"),
  "sd": WhisperLanguage(code: "sd", name: "sindhi", displayName: "Sindhi", displayLocaleName: "سنڌي"),
  "gu": WhisperLanguage(code: "gu", name: "gujarati", displayName: "Gujarati", displayLocaleName: "ગુજરાતી"),
  "am": WhisperLanguage(code: "am", name: "amharic", displayName: "Amharic", displayLocaleName: "አማርኛ"),
  "yi": WhisperLanguage(code: "yi", name: "yiddish", displayName: "Yiddish", displayLocaleName: "ייִדיש"),
  "lo": WhisperLanguage(code: "lo", name: "lao", displayName: "Lao", displayLocaleName: "ລາວ"),
  "uz": WhisperLanguage(code: "uz", name: "uzbek", displayName: "Uzbek", displayLocaleName: "O'zbek"),
  "fo": WhisperLanguage(code: "fo", name: "faroese", displayName: "Faroese", displayLocaleName: "Føroyskt"),
  "ht": WhisperLanguage(
    code: "ht",
    name: "haitian creole",
    displayName: "Haitian Creole",
    displayLocaleName: "Kreyòl Ayisyen",
  ),
  "ps": WhisperLanguage(code: "ps", name: "pashto", displayName: "Pashto", displayLocaleName: "پښتو"),
  "tk": WhisperLanguage(code: "tk", name: "turkmen", displayName: "Turkmen", displayLocaleName: "Türkmen"),
  "nn": WhisperLanguage(code: "nn", name: "nynorsk", displayName: "Nynorsk", displayLocaleName: "Nynorsk"),
  "mt": WhisperLanguage(code: "mt", name: "maltese", displayName: "Maltese", displayLocaleName: "Malti"),
  "sa": WhisperLanguage(code: "sa", name: "sanskrit", displayName: "Sanskrit", displayLocaleName: "संस्कृत"),
  "lb": WhisperLanguage(
    code: "lb",
    name: "luxembourgish",
    displayName: "Luxembourgish",
    displayLocaleName: "Lëtzebuergesch",
  ),
  "my": WhisperLanguage(code: "my", name: "myanmar", displayName: "Myanmar", displayLocaleName: "မြန်မာ"),
  "bo": WhisperLanguage(code: "bo", name: "tibetan", displayName: "Tibetan", displayLocaleName: "བོད་སྐད།"),
  "tl": WhisperLanguage(code: "tl", name: "tagalog", displayName: "Tagalog", displayLocaleName: "Tagalog"),
  "mg": WhisperLanguage(code: "mg", name: "malagasy", displayName: "Malagasy", displayLocaleName: "Malagasy"),
  "as": WhisperLanguage(code: "as", name: "assamese", displayName: "Assamese", displayLocaleName: "অসমীয়া"),
  "tt": WhisperLanguage(code: "tt", name: "tatar", displayName: "Tatar", displayLocaleName: "Татар"),
  "haw": WhisperLanguage(code: "haw", name: "hawaiian", displayName: "Hawaiian", displayLocaleName: "ʻŌlelo Hawaiʻi"),
  "ln": WhisperLanguage(code: "ln", name: "lingala", displayName: "Lingala", displayLocaleName: "Lingála"),
  "ha": WhisperLanguage(code: "ha", name: "hausa", displayName: "Hausa", displayLocaleName: "Hausa"),
  "ba": WhisperLanguage(code: "ba", name: "bashkir", displayName: "Bashkir", displayLocaleName: "Башҡорттар"),
  "jw": WhisperLanguage(code: "jw", name: "javanese", displayName: "Javanese", displayLocaleName: "Basa Jawa"),
  "su": WhisperLanguage(code: "su", name: "sundanese", displayName: "Sundanese", displayLocaleName: "Basa Sunda"),
};

final Map<String, WhisperLanguage> captionLanguages = _getCaptionLanguages();

Map<String, WhisperLanguage> _getCaptionLanguages() {
  // fix zh_CN , zh_TW ... for whisperLanguages
  final Map<String, WhisperLanguage> languages = {};
  for (final lang in whisperLanguages.entries) {
    if (lang.key == "zh") {
      languages["zh_CN"] = WhisperLanguage(
        code: "zh_CN",
        name: "chinese",
        displayName: "Simplified Chinese",
        displayLocaleName: "简体中文",
      );
      languages["zh_TW"] = WhisperLanguage(
        code: "zh_TW",
        name: "chinese",
        displayName: "Traditional Chinese",
        displayLocaleName: "繁體中文",
      );
    } else {
      languages[lang.key] = lang.value;
    }
  }
  return languages;
}
