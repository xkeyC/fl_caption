use std::panic;
use native_dialog::{MessageDialog, MessageType};

pub mod api;
pub mod whisper_caption;
pub mod vad;
mod frb_generated;

pub(crate) fn get_device(try_with_gpu:bool) -> anyhow::Result<candle_core::Device> {
    let device = if try_with_gpu {
        if cfg!(target_os = "macos") {
            candle_core::Device::new_metal(0)?
        } else {
            _try_get_cuda()
        }
    } else {
        candle_core::Device::Cpu
    };
    Ok(device)
}

fn _try_get_cuda() -> candle_core::Device {
    // get a cuda device
    let result = panic::catch_unwind(|| candle_core::Device::cuda_if_available(0).unwrap());
    result.unwrap_or_else(|panic_err| {
        // 尝试从 panic 值中提取有用信息
        let panic_info = if let Some(s) = panic_err.downcast_ref::<String>() {
            s.clone()
        } else if let Some(s) = panic_err.downcast_ref::<&str>() {
            s.to_string()
        } else {
            "Unknow CUDA device initialization error".to_string()
        };
        // show dialog
        MessageDialog::new()
            .set_type(MessageType::Error)
            .set_title("CUDA device initialization error , fall back to CPU")
            .set_text(&panic_info)
            .show_alert()
            .unwrap_or(());
        eprintln!("CUDA device initialization error {}", panic_info);
        // 返回 CPU 设备
        candle_core::Device::Cpu
    })
}