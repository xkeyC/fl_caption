//! Everything below the Flutter API: ONNX Runtime loading, the model
//! catalog and store, ASR/translation engines and the live and file
//! pipelines. `crate::api` only converts types and starts work here.

pub mod agc;
pub mod asr;
pub mod capture;
pub mod catalog;
pub mod filejob;
pub mod lang;
pub mod live;
pub mod pool;
pub mod runtime;
pub mod segmenter;
pub mod store;
pub mod subtitle;
pub mod text;
pub mod translate;

/// Sample rate of everything after capture/decoding: what the VAD and the
/// ASR models take.
pub const SAMPLE_RATE: usize = 16_000;

pub fn samples_to_ms(samples: usize) -> u64 {
    samples as u64 * 1000 / SAMPLE_RATE as u64
}
