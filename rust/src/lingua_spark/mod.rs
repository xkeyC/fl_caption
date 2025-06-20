use anyhow::{anyhow, Context};
use isolang::Language;
use linguaspark::Translator;
use log::info;
use std::fs;
use std::path::PathBuf;

pub mod translation;

pub(crate) fn new_app_state(models_dir: &PathBuf) -> anyhow::Result<translation::AppState> {
    let translator = Translator::new(1).context("Failed to initialize translator")?;
    info!("Loading translation models from {}", models_dir.display());
    let models = load_models_manually(&translator, &models_dir)
        .context("Failed to load translation models")?;
    let state = translation::AppState { translator, models };
    Ok(state)
}
pub(crate) fn load_models_manually(
    translator: &Translator,
    models_dir: &PathBuf,
) -> anyhow::Result<Vec<(Language, Language)>> {
    let mut models = Vec::new();

    for entry in fs::read_dir(models_dir)? {
        let entry = entry?;
        let model_dir_path = entry.path();
        let language_pair = entry.file_name().to_string_lossy().into_owned();

        info!("Looking for models in {}", model_dir_path.display());
        translator.load_model(&language_pair, model_dir_path)?;

        if language_pair.len() >= 4 {
            let from_lang = translation::parse_language_code(&language_pair[0..2])?;
            let to_lang = translation::parse_language_code(&language_pair[2..4])?;
            models.push((from_lang, to_lang));
        } else {
            return Err(anyhow!(
                "Invalid language pair format: '{}'. Expected format like 'enzh', 'jpen'",
                language_pair
            ));
        }
        info!("Loaded model for language pair '{}'", language_pair);
    }

    Ok(models)
}
