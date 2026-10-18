//! Subtitle cues from recognized speech segments, and the file formats.
//!
//! A speech segment (up to ~15 s) becomes one or more cues: split after
//! sentence punctuation, and a sentence too long for one cue in balanced
//! halves at clause marks (else word boundaries), using the token times when
//! the model gives them (SenseVoice) and the characters' share of the
//! segment otherwise (Fun-ASR-Nano).

use super::asr::Recognized;
use super::lang::{is_cjk, width};
use std::fmt::Write as _;

#[derive(Debug, Clone, Default, PartialEq)]
pub struct Cue {
    pub start_ms: u64,
    pub end_ms: u64,
    pub text: String,
    pub translation: Option<String>,
}

#[derive(Debug, Clone, Copy)]
pub struct CueRules {
    pub max_ms: u64,
    /// Display width (CJK characters count two).
    pub max_width: usize,
    /// Cut trailing commas/full stops (subtitle convention for CJK).
    pub strip_end_punctuation: bool,
}

impl Default for CueRules {
    fn default() -> Self {
        Self {
            max_ms: 7_000,
            max_width: 44,
            strip_end_punctuation: true,
        }
    }
}

fn is_sentence_end(ch: char) -> bool {
    matches!(ch, '。' | '！' | '？' | '.' | '!' | '?' | '…' | '；' | ';')
}

fn is_clause_mark(ch: char) -> bool {
    matches!(ch, '，' | ',' | '、' | '：' | ':' | '—')
}

/// The cues of one recognized segment at `start_ms..end_ms` of the file.
pub fn segment_cues(
    start_ms: u64,
    end_ms: u64,
    recognized: &Recognized,
    rules: &CueRules,
) -> Vec<Cue> {
    let text = recognized.text.trim();
    if text.is_empty() {
        return Vec::new();
    }
    let mut units = if recognized.tokens.is_empty() {
        character_units(start_ms, end_ms, text)
    } else {
        token_units(start_ms, end_ms, recognized)
    };
    mark_word_starts(&mut units);
    let mut ranges = Vec::new();
    for sentence in sentences(&units) {
        split_long(&units, sentence, rules, &mut ranges);
    }
    let mut cues: Vec<Cue> = ranges
        .into_iter()
        .map(|range| Cue {
            start_ms: units[range.start].start,
            end_ms: units[range.end - 1].end,
            text: tidy(&join(&units[range]), rules),
            translation: None,
        })
        .filter(|cue| !cue.text.is_empty())
        .collect();
    if let Some(last) = cues.last_mut() {
        last.end_ms = last.end_ms.max(end_ms.min(last.end_ms + 800));
    }
    stretch(&mut cues, end_ms);
    cues
}

/// A token (or character) with its time in the file.
#[derive(Debug, Clone)]
struct Unit {
    text: String,
    start: u64,
    end: u64,
    /// A space goes before it.
    starts_word: bool,
    /// Begins a word (jieba's segmentation for CJK text).
    word_start: bool,
}

/// Marks the units a CJK word begins at, so lines never break inside one.
fn mark_word_starts(units: &mut [Unit]) {
    static JIEBA: std::sync::OnceLock<jieba_rs::Jieba> = std::sync::OnceLock::new();
    if !units.iter().any(|unit| unit.text.chars().any(is_cjk)) {
        return;
    }
    let jieba = JIEBA.get_or_init(jieba_rs::Jieba::new);
    let text: String = units.iter().map(|unit| unit.text.as_str()).collect();
    let starts: std::collections::HashSet<usize> = jieba
        .cut(&text, true)
        .iter()
        .map(|token| token.start)
        .collect();
    let mut at = 0;
    for unit in units.iter_mut() {
        unit.word_start = starts.contains(&at);
        at += unit.text.chars().count();
    }
}

fn token_units(start_ms: u64, end_ms: u64, recognized: &Recognized) -> Vec<Unit> {
    recognized
        .tokens
        .iter()
        .map(|token| Unit {
            text: token.text.clone(),
            start: (start_ms + token.start_ms).min(end_ms),
            end: (start_ms + token.end_ms).min(end_ms),
            starts_word: token.starts_word,
            word_start: true,
        })
        .collect()
}

/// Without token times: characters timed by their share of the segment.
fn character_units(start_ms: u64, end_ms: u64, text: &str) -> Vec<Unit> {
    let chars: Vec<char> = text.chars().collect();
    let visible = chars.iter().filter(|ch| !ch.is_whitespace()).count().max(1) as u64;
    let duration = end_ms.saturating_sub(start_ms);
    let mut units = Vec::new();
    let mut space = false;
    for ch in chars {
        if ch.is_whitespace() {
            space = true;
            continue;
        }
        let index = units.len() as u64;
        units.push(Unit {
            text: ch.to_string(),
            start: start_ms + duration * index / visible,
            end: start_ms + duration * (index + 1) / visible,
            starts_word: std::mem::take(&mut space),
            word_start: true,
        });
    }
    units
}

fn join(units: &[Unit]) -> String {
    let mut text = String::new();
    for unit in units {
        if unit.starts_word && !text.is_empty() {
            text.push(' ');
        }
        text.push_str(&unit.text);
    }
    text
}

fn last_char(unit: &Unit) -> char {
    unit.text.chars().last().unwrap_or(' ')
}

/// Ranges ending after sentence punctuation.
fn sentences(units: &[Unit]) -> Vec<std::ops::Range<usize>> {
    let mut out = Vec::new();
    let mut from = 0;
    for index in 0..units.len() {
        let at_end = index + 1 == units.len();
        if at_end
            || is_sentence_end(last_char(&units[index])) && width(&join(&units[from..=index])) >= 4
        {
            out.push(from..index + 1);
            from = index + 1;
        }
    }
    out
}

/// Whether a cue may start at `units[index]`: between words, or next to a
/// CJK character.
fn boundary(units: &[Unit], index: usize) -> bool {
    let next = &units[index];
    let prev = &units[index - 1];
    next.starts_word
        || is_clause_mark(last_char(prev))
        || next.word_start
            && (next.text.chars().next().is_some_and(is_cjk)
                || prev.text.chars().last().is_some_and(is_cjk))
}

/// Splits `range` in two until each piece fits, at the clause mark (else
/// the word boundary) that balances the halves best: no short tails.
fn split_long(
    units: &[Unit],
    range: std::ops::Range<usize>,
    rules: &CueRules,
    out: &mut Vec<std::ops::Range<usize>>,
) {
    let wide = width(&join(&units[range.clone()]));
    let span = units[range.end - 1]
        .end
        .saturating_sub(units[range.start].start);
    if range.len() < 2 || wide <= rules.max_width && span <= rules.max_ms {
        out.push(range);
        return;
    }
    // The most balanced cut after a clause mark; without one, the most
    // balanced word boundary.
    let mut best: Option<(usize, f64, bool)> = None;
    for cut in range.start + 1..range.end {
        if !boundary(units, cut) {
            continue;
        }
        let clause = is_clause_mark(last_char(&units[cut - 1]));
        let left = width(&join(&units[range.start..cut])) as f64;
        let balance = (left / wide as f64 - 0.5).abs();
        let better = match best {
            None => true,
            Some((_, _, best_clause)) if clause != best_clause => clause,
            Some((_, best_balance, _)) => balance < best_balance,
        };
        if better {
            best = Some((cut, balance, clause));
        }
    }
    match best {
        Some((cut, _, _)) => {
            split_long(units, range.start..cut, rules, out);
            split_long(units, cut..range.end, rules, out);
        }
        None => out.push(range),
    }
}

/// Lets each cue stay up until the next starts (at most 0.8 s longer), so
/// short words do not flash.
fn stretch(cues: &mut [Cue], segment_end: u64) {
    for index in 0..cues.len() {
        let limit = cues
            .get(index + 1)
            .map(|next| next.start_ms)
            .unwrap_or(segment_end);
        let cue = &mut cues[index];
        cue.end_ms = cue
            .end_ms
            .max((cue.end_ms + 800).min(limit))
            .max(cue.start_ms + 300);
    }
}

fn tidy(text: &str, rules: &CueRules) -> String {
    let mut text = text.split_whitespace().collect::<Vec<_>>().join(" ");
    if rules.strip_end_punctuation {
        while let Some(last) = text.chars().last() {
            if matches!(last, '，' | '。' | ',' | '、' | '；' | ';') {
                text.pop();
            } else {
                break;
            }
        }
    }
    text.trim().to_string()
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Format {
    Srt,
    Vtt,
    Lrc,
    Txt,
}

impl Format {
    pub fn parse(name: &str) -> Option<Self> {
        match name.to_ascii_lowercase().as_str() {
            "srt" => Some(Self::Srt),
            "vtt" => Some(Self::Vtt),
            "lrc" => Some(Self::Lrc),
            "txt" => Some(Self::Txt),
            _ => None,
        }
    }

    pub fn extension(self) -> &'static str {
        match self {
            Self::Srt => "srt",
            Self::Vtt => "vtt",
            Self::Lrc => "lrc",
            Self::Txt => "txt",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Lines {
    Source,
    Translation,
    /// Source line, then the translation line.
    Both,
    /// Translation line, then the source line.
    BothTranslationFirst,
}

fn cue_lines(cue: &Cue, lines: Lines) -> Vec<&str> {
    let translation = cue.translation.as_deref().filter(|t| !t.is_empty());
    match (lines, translation) {
        (Lines::Source, _) | (_, None) => vec![cue.text.as_str()],
        (Lines::Translation, Some(t)) => vec![t],
        (Lines::Both, Some(t)) => vec![cue.text.as_str(), t],
        (Lines::BothTranslationFirst, Some(t)) => vec![t, cue.text.as_str()],
    }
}

fn clock(ms: u64, separator: char) -> String {
    format!(
        "{:02}:{:02}:{:02}{separator}{:03}",
        ms / 3_600_000,
        ms / 60_000 % 60,
        ms / 1000 % 60,
        ms % 1000
    )
}

pub fn render(cues: &[Cue], format: Format, lines: Lines, title: &str) -> String {
    let mut out = String::new();
    match format {
        Format::Srt => {
            for (index, cue) in cues.iter().enumerate() {
                let _ = writeln!(out, "{}", index + 1);
                let _ = writeln!(
                    out,
                    "{} --> {}",
                    clock(cue.start_ms, ','),
                    clock(cue.end_ms, ',')
                );
                for line in cue_lines(cue, lines) {
                    let _ = writeln!(out, "{line}");
                }
                out.push('\n');
            }
        }
        Format::Vtt => {
            out.push_str("WEBVTT\n\n");
            for cue in cues {
                let _ = writeln!(
                    out,
                    "{} --> {}",
                    clock(cue.start_ms, '.'),
                    clock(cue.end_ms, '.')
                );
                for line in cue_lines(cue, lines) {
                    let _ = writeln!(out, "{line}");
                }
                out.push('\n');
            }
        }
        Format::Lrc => {
            if !title.is_empty() {
                let _ = writeln!(out, "[ti:{title}]");
            }
            out.push_str("[re:fl_caption]\n");
            for cue in cues {
                let stamp = format!(
                    "[{:02}:{:02}.{:02}]",
                    cue.start_ms / 60_000,
                    cue.start_ms / 1000 % 60,
                    cue.start_ms % 1000 / 10
                );
                // Bilingual LRC: both lines under the same time stamp.
                for line in cue_lines(cue, lines) {
                    let _ = writeln!(out, "{stamp}{line}");
                }
            }
        }
        Format::Txt => {
            for cue in cues {
                let _ = writeln!(out, "{}", cue_lines(cue, lines).join("\n"));
            }
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::engine::asr::Token;

    fn token(start: u64, text: &str) -> Token {
        Token {
            start_ms: start,
            end_ms: start + 60,
            text: text.into(),
            starts_word: false,
        }
    }

    #[test]
    fn tokens_split_at_sentence_ends() {
        let recognized = Recognized {
            text: "今天天气很好。我们去公园吧。".into(),
            tokens: "今天天气很好。我们去公园吧。"
                .chars()
                .enumerate()
                .map(|(i, ch)| token(i as u64 * 200, &ch.to_string()))
                .collect(),
            ..Recognized::default()
        };
        let cues = segment_cues(1000, 4000, &recognized, &CueRules::default());
        assert_eq!(cues.len(), 2);
        assert_eq!(cues[0].text, "今天天气很好");
        assert_eq!(cues[0].start_ms, 1000);
        assert_eq!(cues[1].text, "我们去公园吧");
        assert!(cues[0].end_ms <= cues[1].start_ms);
    }

    #[test]
    fn long_sentences_split_in_balanced_halves() {
        let text = "周末天气很好，我们打算一早出发去郊外的湖边野餐然后在附近的小镇住一晚。";
        let recognized = Recognized {
            text: text.into(),
            tokens: text
                .chars()
                .enumerate()
                .map(|(i, ch)| token(i as u64 * 200, &ch.to_string()))
                .collect(),
            ..Recognized::default()
        };
        let cues = segment_cues(0, 7000, &recognized, &CueRules::default());
        assert_eq!(cues[0].text, "周末天气很好", "{cues:?}");
        // No line breaks inside a word.
        for pair in cues.windows(2) {
            let joint = format!("{}|{}", pair[0].text, pair[1].text);
            for broken in ["野|餐", "郊|外", "附|近", "小|镇", "出|发"] {
                assert!(!joint.contains(broken), "{cues:?}");
            }
        }
        assert!(cues.iter().all(|cue| width(&cue.text) <= 44));
    }

    #[test]
    fn characters_share_the_segment() {
        let recognized = Recognized {
            text: "Hello there. How are you?".into(),
            ..Recognized::default()
        };
        let cues = segment_cues(0, 2500, &recognized, &CueRules::default());
        assert_eq!(cues.len(), 2);
        assert_eq!(cues[1].end_ms, 2500);
        assert_eq!(cues[1].text, "How are you?");
    }

    #[test]
    fn formats_render() {
        let cues = vec![Cue {
            start_ms: 61_500,
            end_ms: 63_000,
            text: "hello".into(),
            translation: Some("你好".into()),
        }];
        let srt = render(&cues, Format::Srt, Lines::Both, "");
        assert_eq!(srt, "1\n00:01:01,500 --> 00:01:03,000\nhello\n你好\n\n");
        let lrc = render(&cues, Format::Lrc, Lines::Translation, "song");
        assert!(lrc.contains("[01:01.50]你好"));
    }
}
