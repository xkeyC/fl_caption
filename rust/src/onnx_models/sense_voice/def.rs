// SenseVoice 特殊标记枚举
#[derive(Debug, Clone, PartialEq)]
pub enum SenseVoiceLanguage {
    Chinese,   // <|zh|>
    English,   // <|en|>
    Cantonese, // <|yue|>
    Japanese,  // <|ja|>
    Korean,    // <|ko|>
    NoSpeech,  // <|nospeech|>
}

#[derive(Debug, Clone, PartialEq)]
pub enum SenseVoiceEmotion {
    Happy,     // <|HAPPY|>
    Sad,       // <|SAD|>
    Angry,     // <|ANGRY|>
    Neutral,   // <|NEUTRAL|>
    Fearful,   // <|FEARFUL|>
    Disgusted, // <|DISGUSTED|>
    Surprised, // <|SURPRISED|>
    Unknown,   // <|EMO_UNKNOWN|>
}

#[derive(Debug, Clone, PartialEq)]
pub enum SenseVoiceEvent {
    Speech,       // <|Speech|>
    BGM,          // <|BGM|>
    Applause,     // <|Applause|>
    Laughter,     // <|Laughter|>
    Cry,          // <|Cry|>
    Sneeze,       // <|Sneeze|>
    Breath,       // <|Breath|>
    Cough,        // <|Cough|>
    Sing,         // <|Sing|>
    SpeechNoise,  // <|Speech_Noise|>
    GBG,          // <|GBG|>
    EventUnknown, // <|Event_UNK|>
}

#[derive(Debug, Clone, PartialEq)]
pub enum SenseVoiceTextNorm {
    WithITN,    // <|withitn|>
    WithoutITN, // <|woitn|>
}

// 解析后的SenseVoice输出结构
#[derive(Debug, Clone)]
pub struct SenseVoiceOutput {
    pub language: Option<SenseVoiceLanguage>,
    pub emotion: Option<SenseVoiceEmotion>,
    pub event: Option<SenseVoiceEvent>,
    pub text_norm: Option<SenseVoiceTextNorm>,
    pub text: String,
    pub emoji: String,
}

impl SenseVoiceLanguage {
    pub(crate) fn from_token(token: &str) -> Option<Self> {
        match token {
            "<|zh|>" => Some(Self::Chinese),
            "<|en|>" => Some(Self::English),
            "<|yue|>" => Some(Self::Cantonese),
            "<|ja|>" => Some(Self::Japanese),
            "<|ko|>" => Some(Self::Korean),
            "<|nospeech|>" => Some(Self::NoSpeech),
            _ => None,
        }
    }

    pub(crate) fn to_emoji(&self) -> &'static str {
        match self {
            Self::Chinese => "",
            Self::English => "",
            Self::Cantonese => "",
            Self::Japanese => "",
            Self::Korean => "",
            Self::NoSpeech => "",
        }
    }
}

impl SenseVoiceEmotion {
    pub(crate) fn from_token(token: &str) -> Option<Self> {
        match token {
            "<|HAPPY|>" => Some(Self::Happy),
            "<|SAD|>" => Some(Self::Sad),
            "<|ANGRY|>" => Some(Self::Angry),
            "<|NEUTRAL|>" => Some(Self::Neutral),
            "<|FEARFUL|>" => Some(Self::Fearful),
            "<|DISGUSTED|>" => Some(Self::Disgusted),
            "<|SURPRISED|>" => Some(Self::Surprised),
            "<|EMO_UNKNOWN|>" => Some(Self::Unknown),
            _ => None,
        }
    }

    pub(crate) fn to_emoji(&self) -> &'static str {
        match self {
            Self::Happy => "😊",
            Self::Sad => "😔",
            Self::Angry => "😡",
            Self::Neutral => "",
            Self::Fearful => "😰",
            Self::Disgusted => "🤢",
            Self::Surprised => "😮",
            Self::Unknown => "",
        }
    }
}

impl SenseVoiceEvent {
    pub(crate) fn from_token(token: &str) -> Option<Self> {
        match token {
            "<|Speech|>" => Some(Self::Speech),
            "<|BGM|>" => Some(Self::BGM),
            "<|Applause|>" => Some(Self::Applause),
            "<|Laughter|>" => Some(Self::Laughter),
            "<|Cry|>" => Some(Self::Cry),
            "<|Sneeze|>" => Some(Self::Sneeze),
            "<|Breath|>" => Some(Self::Breath),
            "<|Cough|>" => Some(Self::Cough),
            "<|Sing|>" => Some(Self::Sing),
            "<|Speech_Noise|>" => Some(Self::SpeechNoise),
            "<|GBG|>" => Some(Self::GBG),
            "<|Event_UNK|>" => Some(Self::EventUnknown),
            _ => None,
        }
    }

    pub(crate) fn to_emoji(&self) -> &'static str {
        match self {
            Self::Speech => "",
            Self::BGM => "🎼",
            Self::Applause => "👏",
            Self::Laughter => "😀",
            Self::Cry => "😭",
            Self::Sneeze => "🤧",
            Self::Breath => "",
            Self::Cough => "😷",
            Self::Sing => "",
            Self::SpeechNoise => "",
            Self::GBG => "",
            Self::EventUnknown => "",
        }
    }
}

impl SenseVoiceTextNorm {
    pub(crate) fn from_token(token: &str) -> Option<Self> {
        match token {
            "<|withitn|>" => Some(Self::WithITN),
            "<|woitn|>" => Some(Self::WithoutITN),
            _ => None,
        }
    }
}
