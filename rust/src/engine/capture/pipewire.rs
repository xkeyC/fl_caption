//! Linux: a PipeWire capture stream. System audio is the default sink's
//! monitor (`stream.capture.sink`); PipeWire converts to the 16 kHz mono
//! F32 format the stream asks for.

use super::{mix_to_mono, Capture, Device, SourceKind};
use anyhow::{anyhow, Result};
use pipewire as pw;
use pw::{properties::properties, spa};
use spa::param::format::{MediaSubtype, MediaType};
use spa::param::format_utils;
use spa::pod::Pod;
use std::sync::mpsc;
use std::time::Duration;

pub fn devices() -> Vec<Device> {
    // Node enumeration needs a registry round trip; the defaults (and a
    // node name typed in the settings) cover what captions need.
    vec![
        Device {
            id: String::new(),
            name: "Default output (monitor)".into(),
            kind: SourceKind::System,
            is_default: true,
        },
        Device {
            id: String::new(),
            name: "Default input".into(),
            kind: SourceKind::Microphone,
            is_default: true,
        },
    ]
}

struct UserData {
    format: spa::param::audio::AudioInfoRaw,
    tx: mpsc::Sender<Vec<f32>>,
}

pub fn start(
    kind: SourceKind,
    target: Option<&str>,
) -> Result<(Capture, mpsc::Receiver<Vec<f32>>)> {
    let (tx, rx) = mpsc::channel::<Vec<f32>>();
    let (ready_tx, ready_rx) = mpsc::channel::<Result<pw::channel::Sender<()>>>();
    let target = target
        .filter(|target| !target.is_empty())
        .map(str::to_string);
    std::thread::Builder::new()
        .name("fl-capture".into())
        .spawn(move || {
            if let Err(error) = run(kind, target, tx, &ready_tx) {
                let _ = ready_tx.send(Err(error));
            }
        })?;
    let quit = ready_rx
        .recv_timeout(Duration::from_secs(10))
        .map_err(|_| anyhow!("PipeWire did not start"))??;
    let name = match kind {
        SourceKind::System => "PipeWire monitor",
        SourceKind::Microphone => "PipeWire input",
    };
    Ok((
        Capture::new(name.to_string(), 16_000, move || {
            let _ = quit.send(());
        }),
        rx,
    ))
}

fn run(
    kind: SourceKind,
    target: Option<String>,
    tx: mpsc::Sender<Vec<f32>>,
    ready: &mpsc::Sender<Result<pw::channel::Sender<()>>>,
) -> Result<()> {
    pw::init();
    let mainloop = pw::main_loop::MainLoop::new(None)?;
    let context = pw::context::Context::new(&mainloop)?;
    let core = context.connect(None)?;

    let (quit_tx, quit_rx) = pw::channel::channel::<()>();
    let _quit = quit_rx.attach(mainloop.loop_(), {
        let mainloop = mainloop.clone();
        move |_| mainloop.quit()
    });

    let mut props = properties! {
        *pw::keys::MEDIA_TYPE => "Audio",
        *pw::keys::MEDIA_CATEGORY => "Capture",
        *pw::keys::MEDIA_ROLE => "Communication",
        *pw::keys::NODE_NAME => "fl_caption",
    };
    if kind == SourceKind::System {
        props.insert(*pw::keys::STREAM_CAPTURE_SINK, "true");
    }
    if let Some(target) = &target {
        props.insert(*pw::keys::TARGET_OBJECT, target.clone());
    }
    let stream = pw::stream::Stream::new(&core, "fl_caption capture", props)?;
    let data = UserData {
        format: Default::default(),
        tx,
    };
    let _listener = stream
        .add_local_listener_with_user_data(data)
        .param_changed(|_, data, id, param| {
            let Some(param) = param else { return };
            if id != pw::spa::param::ParamType::Format.as_raw() {
                return;
            }
            let Ok((media_type, media_subtype)) = format_utils::parse_format(param) else {
                return;
            };
            if media_type != MediaType::Audio || media_subtype != MediaSubtype::Raw {
                return;
            }
            if data.format.parse(param).is_ok() {
                tracing::info!(
                    rate = data.format.rate(),
                    channels = data.format.channels(),
                    "PipeWire format"
                );
            }
        })
        .process(|stream, data| {
            let Some(mut buffer) = stream.dequeue_buffer() else {
                return;
            };
            let datas = buffer.datas_mut();
            let Some(first) = datas.first_mut() else {
                return;
            };
            let size = first.chunk().size() as usize;
            let channels = data.format.channels().max(1) as usize;
            let Some(bytes) = first.data() else { return };
            let bytes = &bytes[..size.min(bytes.len())];
            let interleaved: Vec<f32> = bytes
                .chunks_exact(4)
                .map(|b| f32::from_le_bytes([b[0], b[1], b[2], b[3]]))
                .collect();
            let mut mono = Vec::with_capacity(interleaved.len() / channels);
            mix_to_mono(&interleaved, channels, &mut mono);
            if !mono.is_empty() {
                let _ = data.tx.send(mono);
            }
        })
        .register()?;

    let mut audio_info = spa::param::audio::AudioInfoRaw::new();
    audio_info.set_format(spa::param::audio::AudioFormat::F32LE);
    audio_info.set_rate(16_000);
    audio_info.set_channels(1);
    let object = pw::spa::pod::Object {
        type_: pw::spa::utils::SpaTypes::ObjectParamFormat.as_raw(),
        id: pw::spa::param::ParamType::EnumFormat.as_raw(),
        properties: audio_info.into(),
    };
    let values: Vec<u8> = pw::spa::pod::serialize::PodSerializer::serialize(
        std::io::Cursor::new(Vec::new()),
        &pw::spa::pod::Value::Object(object),
    )?
    .0
    .into_inner();
    let mut params = [Pod::from_bytes(&values).ok_or_else(|| anyhow!("bad format pod"))?];
    stream.connect(
        spa::utils::Direction::Input,
        None,
        pw::stream::StreamFlags::AUTOCONNECT
            | pw::stream::StreamFlags::MAP_BUFFERS
            | pw::stream::StreamFlags::RT_PROCESS,
        &mut params,
    )?;
    let _ = ready.send(Ok(quit_tx));
    mainloop.run();
    tracing::info!("PipeWire capture stopped");
    Ok(())
}
