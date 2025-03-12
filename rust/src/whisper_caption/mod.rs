pub mod multilingual;
pub mod whisper;

use crate::whisper_caption::whisper::{Model, Segment};
use candle_nn::VarBuilder;
use candle_transformers::models::whisper::{self as m, audio, Config};
use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use tokenizers::Tokenizer;
use tokio_util::sync::CancellationToken;

pub async fn launch_caption<F>(
    model_path: String,
    config_data: &str,
    is_quantized: bool,
    tokenizer_data: Vec<u8>,
    audio_device: Option<String>,
    audio_device_is_input: Option<bool>,
    audio_language: Option<String>,
    is_multilingual: Option<bool>,
    cancel_token: CancellationToken,
    with_timestamps: Option<bool>,
    verbose: Option<bool>,
    mut result_callback: F,
) -> anyhow::Result<()>
where
    F: FnMut(Vec<Segment>) + Send + 'static,
{
    let device = candle_core::Device::Cpu;

    let arg_is_multilingual = is_multilingual.unwrap_or(false);
    let arg_language = audio_language;
    let arg_device = audio_device;
    let is_input = audio_device_is_input.unwrap_or(true);

    let config: Config = serde_json::from_str(config_data)?;
    let tokenizer = Tokenizer::from_bytes(tokenizer_data).unwrap();
    let model = if is_quantized {
        let vb = candle_transformers::quantized_var_builder::VarBuilder::from_gguf(
            &model_path,
            &device,
        )?;
        Model::Quantized(m::quantized_model::Whisper::load(&vb, config.clone())?)
    } else {
        let vb = unsafe { VarBuilder::from_mmaped_safetensors(&[model_path], m::DTYPE, &device)? };
        Model::Normal(m::model::Whisper::load(&vb, config.clone())?)
    };
    let seed = 299792458;
    let mut decoder = whisper::Decoder::new(
        model,
        tokenizer.clone(),
        seed,
        &device,
        /* language_token */ None,
        Some(whisper::Task::Transcribe),
        with_timestamps.unwrap_or(false),
        verbose.unwrap_or(false),
    )?;

    let mel_bytes = match config.num_mel_bins {
        80 => include_bytes!("../../whisper/melfilters.bytes").as_slice(),
        128 => include_bytes!("../../whisper/melfilters128.bytes").as_slice(),
        nmel => anyhow::bail!("unexpected num_mel_bins {nmel}"),
    };
    let mut mel_filters = vec![0f32; mel_bytes.len() / 4];
    <byteorder::LittleEndian as byteorder::ByteOrder>::read_f32_into(mel_bytes, &mut mel_filters);

    // Set up the audio device and stream
    let host = cpal::default_host();

    let audio_device = if is_input {
        match arg_device {
            None => host.default_input_device(),
            Some(device) => host
                .input_devices()?
                .find(|x| x.name().map_or(false, |y| y == device)),
        }
    } else {
        match arg_device {
            None => host.default_output_device(),
            Some(device) => host
                .output_devices()?
                .find(|x| x.name().map_or(false, |y| y == device)),
        }
    }
    .expect("failed to find the audio device");

    let audio_config = if is_input {
        audio_device
            .default_input_config()
            .expect("Failed to get default input config")
    } else {
        audio_device
            .default_output_config()
            .expect("Failed to get default output config")
    };

    let device_name = audio_device.name()?;

    println!("audio device -> {device_name:?} config -> {audio_config:?}");

    let channel_count = audio_config.channels() as usize;
    let in_sample_rate = audio_config.sample_rate().0 as usize;
    let resample_ratio = 16000. / in_sample_rate as f64;
    let mut resampler = rubato::FastFixedIn::new(
        resample_ratio,
        10.,
        rubato::PolynomialDegree::Septic,
        1024,
        1,
    )?;

    let (tx, rx) = std::sync::mpsc::channel();

    let stream = if is_input {
        audio_device.build_input_stream(
            &audio_config.config(),
            move |pcm: &[f32], _: &cpal::InputCallbackInfo| {
                let pcm = pcm
                    .iter()
                    .step_by(channel_count)
                    .copied()
                    .collect::<Vec<f32>>();
                if !pcm.is_empty() {
                    tx.send(pcm).unwrap()
                }
            },
            move |err| {
                eprintln!("an error occurred on stream: {}", err);
            },
            None,
        )?
    } else {
        // For output devices, we need to capture the audio being played
        // Note: This is a simplified approach and might need more complex implementation
        audio_device.build_input_stream(
            &audio_config.config(),
            move |pcm: &[f32], _: &cpal::InputCallbackInfo| {
                let pcm = pcm
                    .iter()
                    .step_by(channel_count)
                    .copied()
                    .collect::<Vec<f32>>();
                if !pcm.is_empty() {
                    tx.send(pcm).unwrap()
                }
            },
            move |err| {
                eprintln!("an error occurred on stream: {}", err);
            },
            None,
        )?
    };

    stream.play()?;

    // loop to process the audio data until canceled
    println!("transcribing audio...");
    let mut buffered_pcm = vec![];
    let mut language_token_set = false;

    while let Ok(pcm) = rx.recv() {
        // Check if cancellation was requested
        if cancel_token.is_cancelled() {
            println!("Transcription canceled");
            break;
        }

        use rubato::Resampler;

        buffered_pcm.extend_from_slice(&pcm);
        if buffered_pcm.len() < 3 * in_sample_rate {
            continue;
        }

        let mut resampled_pcm = vec![];
        let full_chunks = buffered_pcm.len() / 1024;
        let remainder = buffered_pcm.len() % 1024;

        for chunk in 0..full_chunks {
            let buffered_pcm = &buffered_pcm[chunk * 1024..(chunk + 1) * 1024];
            let pcm = resampler.process(&[&buffered_pcm], None)?;
            resampled_pcm.extend_from_slice(&pcm[0]);
        }

        let pcm = resampled_pcm;

        if remainder == 0 {
            buffered_pcm.clear();
        } else {
            buffered_pcm.copy_within(full_chunks * 1024.., 0);
            buffered_pcm.truncate(remainder);
        }

        let mel = audio::pcm_to_mel(&config, &pcm, &mel_filters);
        let mel_len = mel.len();
        let mel = candle_core::Tensor::from_vec(
            mel,
            (1, config.num_mel_bins, mel_len / config.num_mel_bins),
            &device,
        )?;

        if !language_token_set {
            let language_token = match (arg_is_multilingual, arg_language.clone()) {
                (true, None) => Some(multilingual::detect_language(
                    decoder.model(),
                    &tokenizer,
                    &mel,
                )?),
                (false, None) => None,
                (true, Some(language)) => {
                    match whisper::token_id(&tokenizer, &format!("<|{language}|>")) {
                        Ok(token_id) => Some(token_id),
                        Err(_) => anyhow::bail!("language {language} is not supported"),
                    }
                }
                (false, Some(_)) => {
                    anyhow::bail!("a language cannot be set for non-multilingual models")
                }
            };
            println!("language_token: {:?}", language_token);
            decoder.set_language_token(language_token);
            language_token_set = true;
        }

        // Run the decoder and get the results
        // Run the decoder and get the results
        let segments = decoder.run(&mel, None)?;

        // Send results through the callback - passing entire segment instead of just text
        result_callback(segments);
        decoder.reset_kv_cache();
    }

    // Ensure the stream is properly stopped
    drop(stream);

    Ok(())
}
