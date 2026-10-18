//! Caption languages: what the translators are told to produce and what
//! the ASR models report.

pub struct Language {
    /// BCP 47-ish code used in settings (`zh`, `zh-Hant`, `en`, ...).
    pub code: &'static str,
    /// The full Chinese name, as Hy-MT2's Chinese prompts want it.
    pub zh: &'static str,
    /// The English name, for English prompts.
    pub en: &'static str,
    /// The language's own name, for the UI.
    pub native: &'static str,
}

/// The languages Hy-MT2 translates between (a subset of its 33 that subtitle
/// users ask for); general LLMs handle them too.
pub const LANGUAGES: &[Language] = &[
    Language {
        code: "zh",
        zh: "中文",
        en: "Simplified Chinese",
        native: "简体中文",
    },
    Language {
        code: "zh-Hant",
        zh: "繁体中文",
        en: "Traditional Chinese",
        native: "繁體中文",
    },
    Language {
        code: "yue",
        zh: "粤语",
        en: "Cantonese",
        native: "粵語",
    },
    Language {
        code: "en",
        zh: "英语",
        en: "English",
        native: "English",
    },
    Language {
        code: "ja",
        zh: "日语",
        en: "Japanese",
        native: "日本語",
    },
    Language {
        code: "ko",
        zh: "韩语",
        en: "Korean",
        native: "한국어",
    },
    Language {
        code: "fr",
        zh: "法语",
        en: "French",
        native: "Français",
    },
    Language {
        code: "de",
        zh: "德语",
        en: "German",
        native: "Deutsch",
    },
    Language {
        code: "es",
        zh: "西班牙语",
        en: "Spanish",
        native: "Español",
    },
    Language {
        code: "pt",
        zh: "葡萄牙语",
        en: "Portuguese",
        native: "Português",
    },
    Language {
        code: "it",
        zh: "意大利语",
        en: "Italian",
        native: "Italiano",
    },
    Language {
        code: "ru",
        zh: "俄语",
        en: "Russian",
        native: "Русский",
    },
    Language {
        code: "uk",
        zh: "乌克兰语",
        en: "Ukrainian",
        native: "Українська",
    },
    Language {
        code: "pl",
        zh: "波兰语",
        en: "Polish",
        native: "Polski",
    },
    Language {
        code: "nl",
        zh: "荷兰语",
        en: "Dutch",
        native: "Nederlands",
    },
    Language {
        code: "tr",
        zh: "土耳其语",
        en: "Turkish",
        native: "Türkçe",
    },
    Language {
        code: "ar",
        zh: "阿拉伯语",
        en: "Arabic",
        native: "العربية",
    },
    Language {
        code: "th",
        zh: "泰语",
        en: "Thai",
        native: "ไทย",
    },
    Language {
        code: "vi",
        zh: "越南语",
        en: "Vietnamese",
        native: "Tiếng Việt",
    },
    Language {
        code: "id",
        zh: "印尼语",
        en: "Indonesian",
        native: "Bahasa Indonesia",
    },
    Language {
        code: "ms",
        zh: "马来语",
        en: "Malay",
        native: "Bahasa Melayu",
    },
    Language {
        code: "hi",
        zh: "印地语",
        en: "Hindi",
        native: "हिन्दी",
    },
];

pub fn find(code: &str) -> Option<&'static Language> {
    LANGUAGES
        .iter()
        .find(|language| language.code.eq_ignore_ascii_case(code))
}

/// The settings code of an ASR language tag (SenseVoice: `zh`, `en`,
/// `yue`, `ja`, `ko`; `nospeech` and unknown tags give `None`).
pub fn from_asr_tag(tag: &str) -> Option<&'static str> {
    match tag {
        "zh" => Some("zh"),
        "en" => Some("en"),
        "yue" => Some("yue"),
        "ja" => Some("ja"),
        "ko" => Some("ko"),
        _ => None,
    }
}

/// Whether text written in `detected` needs no translation into `target`
/// (Simplified and Traditional Chinese count as different).
pub fn same_language(detected: &str, target: &str) -> bool {
    detected.eq_ignore_ascii_case(target)
}

/// Whether `text` is mostly CJK (it decides prompt language and subtitle
/// line widths).
pub fn is_cjk_text(text: &str) -> bool {
    let (mut cjk, mut other) = (0usize, 0usize);
    for ch in text.chars() {
        if is_cjk(ch) {
            cjk += 1;
        } else if ch.is_alphanumeric() {
            other += 1;
        }
    }
    cjk * 2 >= other && cjk > 0
}

pub fn is_cjk(ch: char) -> bool {
    matches!(ch as u32,
        0x3040..=0x30FF   // kana
        | 0x3400..=0x4DBF // CJK ext. A
        | 0x4E00..=0x9FFF // CJK unified
        | 0xAC00..=0xD7AF // Hangul syllables
        | 0xF900..=0xFAFF // CJK compatibility
        | 0x20000..=0x2FFFF)
}

/// Display width: CJK characters count two columns.
pub fn width(text: &str) -> usize {
    text.chars().map(|ch| if is_cjk(ch) { 2 } else { 1 }).sum()
}
