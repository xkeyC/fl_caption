use anyhow::{anyhow, Result};
use isolang::Language;
use linguaspark::Translator;

pub struct AppState {
    pub(crate) translator: Translator,
    pub models: Vec<(Language, Language)>,
}

pub fn parse_language_code(code: &str) -> Result<Language> {
    Language::from_639_1(code.split('-').next().unwrap_or(code)).ok_or_else(|| {
        anyhow!(
            "Invalid language code: '{}'. Please use ISO 639-1 format.",
            code
        )
    })
}

fn get_iso_code(lang: &Language) -> Result<&'static str> {
    lang.to_639_1()
        .ok_or_else(|| anyhow!("Language '{}' doesn't have an ISO 639-1 code", lang))
}

pub fn detect_language_code(text: &str) -> Result<&'static str> {
    get_iso_code(
        &Language::from_639_3(whichlang::detect_language(text).three_letter_code())
            .ok_or_else(|| anyhow!("Failed to identify language for text: '{}'", text))?,
    )
}

pub(crate) fn perform_translation(
    state: &AppState,
    text: &str,
    from_lang: Option<String>,
    to_lang: &str,
) -> Result<(String, String, String)> {
    let source_lang = match from_lang.as_deref() {
        None | Some("") | Some("auto") => {
            if state.models.len() == 1 {
                // If there's only one model, use it as the source language
                state
                    .models
                    .first()
                    .map(|model| model.0)
                    .unwrap_or(Language::Eng)
            } else {
                Language::from_639_3(whichlang::detect_language(text).three_letter_code())
                    .ok_or_else(|| anyhow!("Failed to detect language for text: '{}'", text))?
            }
        }
        Some(code) => parse_language_code(code)?,
    };

    let target_lang = parse_language_code(to_lang)?;

    let from_code = get_iso_code(&source_lang)?;
    let to_code = get_iso_code(&target_lang)?;

    if !state.translator.is_supported(from_code, to_code)? {
        return Err(anyhow!(
            "Translation from '{}' to '{}' is not supported",
            from_code,
            to_code
        ));
    }

    let translated_text = state.translator.translate(from_code, to_code, text)?;

    Ok((translated_text, from_code.to_string(), to_code.to_string()))
}
