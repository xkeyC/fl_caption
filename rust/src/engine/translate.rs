//! Caption translation with a local model (infra's chat adapter, which keeps
//! the KV cache of the previous request and only prefills what follows the
//! shared prefix) or an OpenAI-compatible API.
//!
//! Prompts are laid out so the prefix stays the same from line to line:
//! instructions first, then the previous lines (appended to, and trimmed a
//! block at a time rather than one line per request), then the line itself
//! with the glossary terms it uses. A partial line's request shares
//! everything but its tail with the final line's.
//!
//! - Hy-MT2 (no system prompt, one user turn): its official background and
//!   terminology templates, the previous lines as background.
//! - General chat models / APIs: a system prompt and the previous lines as
//!   user/assistant turns.
//!
//! Re-translating a growing line would re-word it every time (the same
//! meaning, a different variant). A local model therefore continues the
//! line's previous translation (a [`Draft`]): its whole clauses that the
//! translation before it already had (two translations agreed, so not a
//! one-off guess) and that the still unchanged source supports are
//! prefilled as the start of the reply, and only the rest is generated.
//! Where recognition revised earlier words, less is kept, so the
//! translation is corrected from there on. The whole draft is also given
//! as a reference (any backend): keep its wording where it still fits, so
//! the open clause is not re-worded either unless the source changed.

use super::catalog::Engine;
use super::lang::{self, Language};
use super::pool::SharedChat;
use super::text::{matching_terms, Term};
use anyhow::{anyhow, bail, Context, Result};
use local_core::{ChatMessage, ChatOptions, InferenceEvent};
use std::io::BufRead;
use std::time::{Duration, Instant};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PromptStyle {
    HyMt,
    Chat,
}

impl PromptStyle {
    pub fn for_engine(engine: Engine) -> Self {
        match engine {
            Engine::HyMt => Self::HyMt,
            _ => Self::Chat,
        }
    }
}

#[derive(Debug, Clone)]
pub struct ApiConfig {
    /// e.g. `https://api.openai.com/v1` (`/chat/completions` is appended).
    pub base_url: String,
    pub api_key: String,
    pub model: String,
    pub temperature: f32,
    /// Hy-MT2 served by an API (vLLM, Tencent's endpoint) uses its prompts.
    pub style: PromptStyle,
}

pub enum Backend {
    Local {
        model: SharedChat,
        style: PromptStyle,
    },
    Api(ApiClient),
}

#[derive(Debug, Clone)]
pub struct TranslatorConfig {
    pub target: String,
    /// What the user tells the translator about the content (a game, a
    /// talk...): background for Hy-MT2, part of the system prompt else.
    pub background: String,
    pub glossary: Vec<Term>,
    /// Previous lines given as context (0: none).
    pub context_lines: usize,
    pub temperature: f32,
}

/// An earlier translation of the line being translated again (its partial
/// text, before it grew or was revised).
#[derive(Debug, Clone, Copy)]
pub struct Draft<'a> {
    pub source: &'a str,
    pub translation: &'a str,
    /// The translation before that one, if the line had one.
    pub earlier: Option<&'a str>,
    /// Also show the model the whole draft as a reference.
    pub reference: bool,
}

#[derive(Debug, Clone, Default)]
pub struct Translation {
    pub text: String,
    pub prompt_tokens: usize,
    pub cached_tokens: usize,
    pub first_token_ms: u64,
    pub total_ms: u64,
    /// Characters kept from the draft (forced, not generated).
    pub kept_chars: usize,
}

pub struct Translator {
    backend: Backend,
    config: TranslatorConfig,
    /// (source line as sent, translation)
    history: Vec<(String, String)>,
}

/// Terms named per line at most.
const MAX_TERMS_PER_LINE: usize = 12;

impl Translator {
    pub fn new(backend: Backend, config: TranslatorConfig) -> Self {
        Self {
            backend,
            config,
            history: Vec::new(),
        }
    }

    pub fn set_config(&mut self, config: TranslatorConfig) {
        if config.target != self.config.target || config.background != self.config.background {
            self.history.clear();
        }
        self.config = config;
    }

    pub fn config(&self) -> &TranslatorConfig {
        &self.config
    }

    pub fn clear_history(&mut self) {
        self.history.clear();
    }

    fn style(&self) -> PromptStyle {
        match &self.backend {
            Backend::Local { style, .. } => *style,
            Backend::Api(client) => client.config.style,
        }
    }

    /// Translates `text`; `commit` keeps the pair as context for the next
    /// lines (final lines; partial ones are not kept). `draft`: the line's
    /// previous translation, whose stable part a local model keeps.
    /// `on_delta` gets the translation so far and returns `false` to stop
    /// (then `None`).
    pub fn translate(
        &mut self,
        text: &str,
        commit: bool,
        draft: Option<Draft>,
        on_delta: &mut dyn FnMut(&str) -> bool,
    ) -> Result<Option<Translation>> {
        let text = text.trim();
        if text.is_empty() {
            return Ok(Some(Translation::default()));
        }
        let target = lang::find(&self.config.target)
            .ok_or_else(|| anyhow!("unknown target language {}", self.config.target))?;
        let reference = draft
            .filter(|draft| draft.reference)
            .map(|draft| draft.translation.trim())
            .filter(|translation| !translation.is_empty());
        let messages = match self.style() {
            PromptStyle::HyMt => self.hymt_messages(text, target, reference),
            PromptStyle::Chat => self.chat_messages(text, target, reference),
        };
        let max_tokens = (text.chars().count() * 4 + 48).min(768);
        // An API cannot be made to continue a reply.
        let kept = match (&self.backend, draft) {
            (Backend::Local { .. }, Some(draft)) => stable_prefix(draft, text),
            _ => "",
        };
        let started = Instant::now();
        let mut output = kept.to_string();
        let mut first_token_ms = 0;
        let mut cancelled = false;
        let mut emit = |piece: &str| -> bool {
            if first_token_ms == 0 && !piece.is_empty() {
                first_token_ms = started.elapsed().as_millis() as u64;
            }
            output.push_str(piece);
            let keep = on_delta(clean_output(&output));
            cancelled |= !keep;
            keep
        };
        let (prompt_tokens, cached_tokens) = match &mut self.backend {
            Backend::Local { model, .. } => {
                let options = ChatOptions {
                    max_tokens: Some(max_tokens),
                    temperature: Some(self.config.temperature),
                    top_p: Some(0.6),
                    top_k: Some(20),
                    ..ChatOptions::default()
                };
                let mut model = model.lock().unwrap_or_else(|e| e.into_inner());
                let result = model
                    .complete_after(&messages, &[], kept, &options, &mut |event| match event {
                        InferenceEvent::ChatDelta { content } => emit(&content),
                        _ => true,
                    })
                    .map_err(|error| anyhow!("{error}"))?;
                match result {
                    local_core::InferenceOutput::ChatCompletion { usage, .. } => {
                        (usage.prompt_tokens, usage.cached_prompt_tokens)
                    }
                    _ => (0, 0),
                }
            }
            Backend::Api(client) => {
                client.complete(&messages, max_tokens, &mut emit)?;
                (0, 0)
            }
        };
        if cancelled {
            return Ok(None);
        }
        let translation = clean_output(&output).to_string();
        if commit {
            // The chat style replays each line as it was sent (with its
            // glossary note), so the next prompt starts with this one's.
            let sent = match self.style() {
                PromptStyle::Chat => self.chat_line(text),
                PromptStyle::HyMt => text.to_string(),
            };
            self.remember(&sent, &translation);
        }
        Ok(Some(Translation {
            text: translation,
            prompt_tokens,
            cached_tokens,
            first_token_ms,
            total_ms: started.elapsed().as_millis() as u64,
            kept_chars: kept.chars().count(),
        }))
    }

    fn remember(&mut self, source: &str, translation: &str) {
        let keep = self.config.context_lines;
        if keep == 0 {
            return;
        }
        self.history
            .push((source.to_string(), translation.to_string()));
        // Trimmed a block at a time: the prompt prefix (and its KV cache)
        // survives all but every `keep`-th line.
        if self.history.len() > keep * 2 {
            let drop = self.history.len() - keep;
            self.history.drain(..drop);
        }
    }

    fn terms_for(&self, text: &str) -> Vec<&Term> {
        matching_terms(text, &self.config.glossary, MAX_TERMS_PER_LINE)
    }

    /// Hy-MT2: one user turn, Chinese prompts when Chinese is involved
    /// (the model card's advice), English ones otherwise.
    fn hymt_messages(
        &self,
        text: &str,
        target: &Language,
        draft: Option<&str>,
    ) -> Vec<ChatMessage> {
        let chinese =
            target.code.starts_with("zh") || target.code == "yue" || lang::is_cjk_text(text);
        let mut prompt = String::new();
        let background = self.config.background.trim();
        let has_background = !background.is_empty() || !self.history.is_empty();
        if has_background {
            prompt.push_str(if chinese {
                "【背景信息】\n"
            } else {
                "[Background Information]\n"
            });
            if !background.is_empty() {
                prompt.push_str(background);
                prompt.push('\n');
            }
            if !self.history.is_empty() {
                prompt.push_str(if chinese {
                    "前文（原文 => 译文）：\n"
                } else {
                    "Previous lines (source => translation):\n"
                });
                for (source, translation) in &self.history {
                    prompt.push_str(&format!("{source} => {translation}\n"));
                }
            }
            prompt.push('\n');
        }
        let terms = self.terms_for(text);
        if !terms.is_empty() {
            prompt.push_str(if chinese {
                "参考下面的翻译：\n"
            } else {
                "Reference the following translations:\n"
            });
            for term in &terms {
                if chinese {
                    prompt.push_str(&format!(
                        "{} 翻译成 {}\n",
                        term.source.trim(),
                        term.target.trim()
                    ));
                } else {
                    prompt.push_str(&format!(
                        "{} translates to {}\n",
                        term.source.trim(),
                        term.target.trim()
                    ));
                }
            }
            prompt.push('\n');
        }
        if let Some(draft) = draft {
            if chinese {
                prompt.push_str(&format!(
                    "这句话此前的译文草稿：{draft}\n请尽量沿用草稿的措辞，只修改与原文不一致的地方并补全。\n\n"
                ));
            } else {
                prompt.push_str(&format!(
                    "Draft translation of this text so far: {draft}\nKeep the draft's wording where it still fits; change only what differs from the text, and complete it.\n\n"
                ));
            }
        }
        if chinese {
            if has_background {
                prompt.push_str(&format!("请结合背景信息将以下文本翻译为{}，注意只需要输出翻译后的结果，不要额外解释：\n\n", target.zh));
            } else {
                prompt.push_str(&format!(
                    "将以下文本翻译为{}，注意只需要输出翻译后的结果，不要额外解释：\n\n",
                    target.zh
                ));
            }
        } else if has_background {
            prompt.push_str(&format!("Please translate the following text into {}, taking the provided background information into consideration. Note that you should only output the translated result without any additional explanation:\n\n", target.en));
        } else {
            prompt.push_str(&format!("Translate the following text into {}. Note that you should only output the translated result without any additional explanation:\n\n", target.en));
        }
        prompt.push_str(text);
        vec![user(prompt)]
    }

    fn chat_messages(
        &self,
        text: &str,
        target: &Language,
        draft: Option<&str>,
    ) -> Vec<ChatMessage> {
        let mut system = format!(
            "You are a professional real-time subtitle translator. Translate each user message into {} ({}). \
             The messages are speech recognition output: they may be incomplete or contain recognition errors; \
             translate the intended meaning naturally and concisely, as a subtitle. \
             A message may end with a [Glossary] note giving required translations of terms: use them, and never output the note. \
             A message may also end with a [Draft] note: the translation already shown for an earlier, shorter version of the line. \
             Keep its wording where it still fits, change only what the message changed, complete it, and never output the note. \
             Output only the translation, with no quotes, explanations or source text. \
             If a message is already in {}, output it unchanged except for fixing obvious recognition errors.",
            target.en, target.native, target.en
        );
        let background = self.config.background.trim();
        if !background.is_empty() {
            system.push_str("\n\nAbout the content: ");
            system.push_str(background);
        }
        let mut messages = vec![ChatMessage {
            role: "system".into(),
            content: Some(system),
            ..ChatMessage::default()
        }];
        for (source, translation) in &self.history {
            messages.push(user(source.clone()));
            messages.push(ChatMessage {
                role: "assistant".into(),
                content: Some(translation.clone()),
                ..ChatMessage::default()
            });
        }
        let line = self.chat_line(text);
        messages.push(user(match draft {
            Some(draft) => format!("{line}\n[Draft: {draft}]"),
            None => line,
        }));
        messages
    }

    /// A line as the chat style sends it (and keeps it in the history).
    fn chat_line(&self, text: &str) -> String {
        let terms = self.terms_for(text);
        if terms.is_empty() || self.style() != PromptStyle::Chat {
            return text.to_string();
        }
        let notes = terms
            .iter()
            .map(|term| format!("{} = {}", term.source.trim(), term.target.trim()))
            .collect::<Vec<_>>()
            .join("; ");
        format!("{text}\n[Glossary: {notes}]")
    }
}

/// Clause ends: a draft is kept up to one of these.
const CLAUSE_ENDS: &[char] = &[
    '，', '。', '！', '？', '；', '：', '、', ',', '.', '!', '?', ';', ':', '…',
];

/// How many characters of `previous` (letters and digits only) the new
/// recognition `source` still holds unchanged: up to the first character
/// it dropped, or before which it has new ones. Only the line's first few
/// characters may differ (recognition often re-hears a line's first word:
/// "Just due to" -> "es due to"); a word changed later ("invade" ->
/// "evade") ends the unchanged part there.
fn unchanged_share(previous: &[char], source: &[char]) -> usize {
    let (n, m) = (previous.len(), source.len());
    let head = (n / 5).min(5);
    // lcs[i * (m + 1) + j]: the longest common subsequence of
    // previous[i..] and source[j..].
    let mut lcs = vec![0u32; (n + 1) * (m + 1)];
    let at = |i: usize, j: usize| i * (m + 1) + j;
    for i in (0..n).rev() {
        for j in (0..m).rev() {
            lcs[at(i, j)] = if previous[i] == source[j] {
                lcs[at(i + 1, j + 1)] + 1
            } else {
                lcs[at(i + 1, j)].max(lcs[at(i, j + 1)])
            };
        }
    }
    // Walk an optimal alignment from the start.
    let (mut i, mut j) = (0, 0);
    let mut matched_at: Option<usize> = None;
    while i < n && j < m {
        if previous[i] == source[j] && lcs[at(i, j)] == lcs[at(i + 1, j + 1)] + 1 {
            if i >= head && matched_at.is_some_and(|last| j > last + 1) {
                return i;
            }
            matched_at = Some(j);
            i += 1;
            j += 1;
        } else if lcs[at(i + 1, j)] >= lcs[at(i, j + 1)] {
            if i >= head {
                return i;
            }
            i += 1;
        } else {
            j += 1;
        }
    }
    i
}

fn letters(text: &str) -> Vec<char> {
    text.chars()
        .filter(|c| c.is_alphanumeric())
        .flat_map(char::to_lowercase)
        .collect()
}

/// What a new translation of `source` keeps of the draft: its whole
/// clauses that the earlier translation began with too, within the share
/// matching the unchanged part of the source, less the clause that share
/// ends in (when all of it is unchanged: the last one, which new words may
/// change). No trailing space: the model starts its continuation with one.
fn stable_prefix<'a>(draft: Draft<'a>, source: &str) -> &'a str {
    let Some(earlier) = draft.earlier else {
        return "";
    };
    let previous = letters(draft.source);
    if previous.is_empty() {
        return "";
    }
    let unchanged = unchanged_share(&previous, &letters(source));
    let translation = draft.translation;
    let all: Vec<(usize, char)> = translation.trim_end().char_indices().collect();
    // A draft's closing mark only says the draft ended.
    let mut n = all.len();
    while n > 0 && (CLAUSE_ENDS.contains(&all[n - 1].1) || all[n - 1].1.is_whitespace()) {
        n -= 1;
    }
    let supported = n * unchanged / previous.len();
    let open_from = if unchanged == previous.len() {
        n
    } else {
        supported
    };
    // Two translations in a row agreed on this much.
    let agreed = translation
        .chars()
        .zip(earlier.chars())
        .take_while(|(a, b)| a == b)
        .count();
    let limit = open_from.saturating_sub(1).min(agreed);
    let Some(mark) = all[..limit.min(n)]
        .iter()
        .rposition(|&(_, c)| CLAUSE_ENDS.contains(&c))
    else {
        return "";
    };
    let kept = match all.get(mark + 1) {
        Some(&(offset, _)) => &translation[..offset],
        None => translation,
    }
    .trim_end();
    if kept.chars().count() < 2 {
        ""
    } else {
        kept
    }
}

fn user(content: String) -> ChatMessage {
    ChatMessage {
        role: "user".into(),
        content: Some(content),
        ..ChatMessage::default()
    }
}

/// What a translation should not carry: surrounding white space and quotes
/// some models add.
fn clean_output(text: &str) -> &str {
    let text = text.trim();
    let text = text
        .strip_prefix('"')
        .and_then(|inner| inner.strip_suffix('"'))
        .unwrap_or(text);
    text.trim()
}

// ------------------------------------------------------------------ API

pub struct ApiClient {
    pub config: ApiConfig,
    client: reqwest::blocking::Client,
}

impl ApiClient {
    pub fn new(config: ApiConfig) -> Result<Self> {
        if config.base_url.trim().is_empty() || config.model.trim().is_empty() {
            bail!("the API needs a base URL and a model name");
        }
        Ok(Self {
            client: reqwest::blocking::Client::builder()
                .connect_timeout(Duration::from_secs(10))
                .timeout(Duration::from_secs(60))
                .build()?,
            config,
        })
    }

    fn url(&self) -> String {
        let base = self.config.base_url.trim().trim_end_matches('/');
        if base.ends_with("/chat/completions") {
            base.to_string()
        } else {
            format!("{base}/chat/completions")
        }
    }

    /// A streamed chat completion; `on_delta` gets each content piece and
    /// returns `false` to stop reading.
    pub fn complete(
        &self,
        messages: &[ChatMessage],
        max_tokens: usize,
        on_delta: &mut dyn FnMut(&str) -> bool,
    ) -> Result<()> {
        let messages: Vec<serde_json::Value> = messages
            .iter()
            .map(|message| {
                serde_json::json!({
                    "role": message.role,
                    "content": message.content.clone().unwrap_or_default(),
                })
            })
            .collect();
        let body = serde_json::json!({
            "model": self.config.model,
            "messages": messages,
            "temperature": self.config.temperature,
            "max_tokens": max_tokens,
            "stream": true,
        });
        let mut request = self.client.post(self.url()).json(&body);
        if !self.config.api_key.trim().is_empty() {
            request = request.bearer_auth(self.config.api_key.trim());
        }
        let response = request.send().context("API request")?;
        let status = response.status();
        if !status.is_success() {
            let text = response.text().unwrap_or_default();
            bail!(
                "API returned {status}: {}",
                text.chars().take(300).collect::<String>()
            );
        }
        let reader = std::io::BufReader::new(response);
        for line in reader.lines() {
            let line = line.context("API stream")?;
            let Some(data) = line.strip_prefix("data:") else {
                continue;
            };
            let data = data.trim();
            if data == "[DONE]" {
                break;
            }
            let Ok(json) = serde_json::from_str::<serde_json::Value>(data) else {
                continue;
            };
            if let Some(content) = json["choices"][0]["delta"]["content"].as_str() {
                if !content.is_empty() && !on_delta(content) {
                    break;
                }
            }
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::{stable_prefix, Draft};

    fn kept<'a>(
        source: &'a str,
        translation: &'a str,
        earlier: Option<&'a str>,
        new: &str,
    ) -> &'a str {
        stable_prefix(
            Draft {
                source,
                translation,
                earlier,
                reference: false,
            },
            new,
        )
    }

    #[test]
    fn a_growing_line_keeps_its_agreed_clauses() {
        let k = kept(
            "你好，我来给",
            "Hello, I'm going to",
            Some("Hello, I will"),
            "你好，我来给大家讲个故事",
        );
        assert_eq!(k, "Hello,");
        let k = kept(
            "Park the ship near the hangar, and",
            "把飞船停在机库附近，然后",
            Some("把飞船停在机库附近，和"),
            "Park the ship near the hangar, and meet me at the bar.",
        );
        assert_eq!(k, "把飞船停在机库附近，");
    }

    #[test]
    fn a_clause_one_translation_had_is_not_kept() {
        // The first translation of the line: nothing to agree with.
        assert_eq!(
            kept(
                "你好，我来给",
                "Hello, I'm going to",
                None,
                "你好，我来给大家"
            ),
            ""
        );
        // The earlier translation worded the clause differently.
        let k = kept(
            "你好，我来给",
            "Hello, I'm going to",
            Some("Hi, I"),
            "你好，我来给大家讲个故事",
        );
        assert_eq!(k, "");
    }

    #[test]
    fn an_open_clause_is_never_kept() {
        // A guess at an unfinished sentence must not be locked in.
        let k = kept(
            "Insects were the first animals",
            "昆虫是首先被发现的动物。",
            Some("昆虫是首先被提到的。"),
            "Insects were the first animals to take to the air.",
        );
        assert_eq!(k, "");
    }

    #[test]
    fn a_re_heard_first_word_does_not_drop_the_draft() {
        let k = kept(
            "Just due to Auckland straddling two harbors, the most",
            "由于奥克兰横跨两个港口，最受欢迎的",
            Some("由于奥克兰横跨两个港口，最"),
            "es due to Auckland straddling two harbors, the most popular ones",
        );
        assert_eq!(k, "由于奥克兰横跨两个港口，");
    }

    #[test]
    fn a_revised_source_keeps_only_the_unchanged_share() {
        // The second half was re-recognized: only the first clause stays.
        let k = kept(
            "今天天气很好，我们去公园玩",
            "今天天气很好，我们去公园玩",
            Some("今天天气很好，我们去公园"),
            "今天天气很好，我们去游乐园",
        );
        assert_eq!(k, "今天天气很好，");
        // Changed from the start: nothing stays.
        assert_eq!(
            kept(
                "他说，好的",
                "He said, OK",
                Some("He said, OK"),
                "她说，好的"
            ),
            ""
        );
    }

    #[test]
    fn a_word_re_heard_mid_line_drops_the_clauses_after_it() {
        // "invadevade" was "evade": the clause translated from it goes.
        let k = kept(
            "Their ability to fly, it helped them invadevade enemies, and find food",
            "它们会飞，这帮助它们攻击敌人，并寻找食物",
            Some("它们会飞，这帮助它们攻击敌人，并"),
            "Their ability to fly, it helped them evade enemies, and find food and mates",
        );
        assert_eq!(k, "它们会飞，");
    }

    #[test]
    fn an_unchanged_source_keeps_all_but_the_last_clause() {
        let k = kept(
            "一，二，三。",
            "One, two, three.",
            Some("One, two, three."),
            "一，二，三。",
        );
        assert_eq!(k, "One, two,");
    }
}
