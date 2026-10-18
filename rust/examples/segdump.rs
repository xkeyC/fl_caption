//! Prints the utterances the live segmenter cuts from a file (debugging).
//! `segdump <audio> [max segment ms]`
use rust_lib_fl_caption::engine::segmenter::{Segmenter, SegmenterConfig};
use rust_lib_fl_caption::engine::{runtime, samples_to_ms};

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    runtime::init(&[std::env::current_dir().unwrap()]);
    let mut config = SegmenterConfig::live();
    if let Some(max) = args.get(1).and_then(|v| v.parse().ok()) {
        config.max_segment_ms = max;
    }
    let vad = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../assets/models/silero_vad.onnx");
    let mut segmenter = Segmenter::new(&vad, config).unwrap();
    let mut stream =
        local_adapter_sensevoice_asr::AudioStream::open(std::path::Path::new(&args[0])).unwrap();
    let mut chunk = Vec::new();
    let mut fed = 0usize;
    let mut was_ongoing = false;
    let mut agc = std::env::var_os("FL_CAPTION_NO_AGC")
        .is_none()
        .then(rust_lib_fl_caption::engine::agc::AutoGain::default);
    loop {
        chunk.clear();
        let more = stream.read(&mut chunk).unwrap();
        for piece in chunk.chunks(320) {
            fed += piece.len();
            let mut piece = piece.to_vec();
            if let Some(agc) = agc.as_mut() {
                agc.process(&mut piece);
            }
            for u in segmenter.push(&piece).unwrap() {
                println!(
                    "utterance {:>6}..{:>6} ms",
                    samples_to_ms(u.start),
                    samples_to_ms(u.end)
                );
            }
            let ongoing = segmenter.ongoing().is_some();
            if ongoing != was_ongoing {
                println!("  at {:>6} ms ongoing={ongoing}", samples_to_ms(fed));
                was_ongoing = ongoing;
            }
        }
        if !more {
            break;
        }
    }
    if let Some(u) = segmenter.finish() {
        println!(
            "utterance {:>6}..{:>6} ms (end)",
            samples_to_ms(u.start),
            samples_to_ms(u.end)
        );
    }
}
