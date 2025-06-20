use crate::lingua_spark;
use std::path::PathBuf;

pub async fn init_engine(models_dir: String) -> anyhow::Result<()> {
    let models_path = PathBuf::from(models_dir);
    let _ = lingua_spark::new_app_state(&models_path)?;
    Ok(())
}
