use crate::lingua_spark;
use crate::lingua_spark::translation::AppState;
use std::path::PathBuf;
use std::panic;

pub struct LanguagePair {
    pub from: String,
    pub to: String,
}

pub struct TranslatorResult {
    pub  pair : LanguagePair,
    pub source_text: String,
    pub translated_text: String,
}

pub async fn init_engine(models_dir: String) -> anyhow::Result<AppState> {
    println!("Initializing engine form dir: {}", models_dir);
    let models_path = PathBuf::from(models_dir);
    let engine = lingua_spark::new_app_state(&models_path)?;
    Ok(engine)
}

pub async fn get_models(engine: &AppState) -> anyhow::Result<Vec<LanguagePair>> {
    let mut models = Vec::new();
    for (from_lang, to_lang) in &engine.models {
        models.push(LanguagePair {
            from: from_lang.to_name().to_string(),
            to: to_lang.to_name().to_string(),
        });
    }
    Ok(models)
}

pub async fn translate(
    engine: &AppState,
    from: Option<String>,
    to: String,
    text: String,
) -> anyhow::Result<TranslatorResult> {
    let result = panic::catch_unwind(|| {
        lingua_spark::translation::perform_translation(engine, &text, from, &to)
    });

    match result {
        Ok(translation_result) => {
            let r = translation_result?;
            Ok(TranslatorResult {
                pair: LanguagePair {
                    from: r.1.to_string(),
                    to: r.2.to_string(),
                },
                source_text: text,
                translated_text: r.0,
            })
        }
        Err(panic_error) => {
            let panic_msg = if let Some(s) = panic_error.downcast_ref::<&str>() {
                s.to_string()
            } else if let Some(s) = panic_error.downcast_ref::<String>() {
                s.clone()
            } else {
                "Unknown panic occurred during translation".to_string()
            };
            Err(anyhow::anyhow!("Translation failed due to panic: {}", panic_msg))
        }
    }
}
