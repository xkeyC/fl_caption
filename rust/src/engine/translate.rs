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

#[derive(Debug, Clone, Default)]
pub struct Translation {
    pub text: String,
    pub prompt_tokens: usize,
    pub cached_tokens: usize,
    pub first_token_ms: u64,
    pub total_ms: u64,
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
    /// lines (final lines; partial ones are not kept). `on_delta` gets the
    /// translation so far and returns `false` to stop (then `None`).
    pub fn translate(
        &mut self,
        text: &str,
        commit: bool,
        on_delta: &mut dyn FnMut(&str) -> bool,
    ) -> Result<Option<Translation>> {
        let text = text.trim();
        if text.is_empty() {
            return Ok(Some(Translation::default()));
        }
        let target = lang::find(&self.config.target)
            .ok_or_else(|| anyhow!("unknown target language {}", self.config.target))?;
        let messages = match self.style() {
            PromptStyle::HyMt => self.hymt_messages(text, target),
            PromptStyle::Chat => self.chat_messages(text, target),
        };
        let max_tokens = (text.chars().count() * 4 + 48).min(768);
        let started = Instant::now();
        let mut output = String::new();
        let mut first_token_ms = 0;
        let mut cancelled = false;
        let mut emit = |piece: &str| -> bool {
            if output.is_empty() && !piece.is_empty() {
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
                    .complete(&messages, &[], &options, &mut |event| match event {
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
    fn hymt_messages(&self, text: &str, target: &Language) -> Vec<ChatMessage> {
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

    fn chat_messages(&self, text: &str, target: &Language) -> Vec<ChatMessage> {
        let mut system = format!(
            "You are a professional real-time subtitle translator. Translate each user message into {} ({}). \
             The messages are speech recognition output: they may be incomplete or contain recognition errors; \
             translate the intended meaning naturally and concisely, as a subtitle. \
             A message may end with a [Glossary] note giving required translations of terms: use them, and never output the note. \
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
        messages.push(user(self.chat_line(text)));
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
