use anyhow::Result;

use crate::get_device;
use candle_core::{DType, Tensor};
use candle_onnx::onnx;

struct VadModelState {
    frame_size: usize,
    sample_rate: Tensor,
}

pub struct VadDevice {
    device: candle_core::Device,
    model: onnx::ModelProto,
    state: VadModelState,
    context_size: usize,
}

pub struct VadResult {
    pub chunk_results: Vec<f32>,
    pub pcm_results: Vec<f32>,
    pub res_len: f32,
    pub prediction: f32,
    pub filtered_count: usize,
}

impl VadDevice {
    pub fn check_vad(
        &self,
        audio_sample: Vec<f32>,
        filters_value: Option<f32>,
    ) -> Result<VadResult> {
        let start = std::time::Instant::now();
        // println!(
        //     "check_vad start audio_sample len =  {:?}",
        //     audio_sample.len()
        // );
        let context_size = self.context_size;
        let device = &self.device;
        let model = &self.model;

        let mut state = Tensor::zeros((2, 1, 128), DType::F32, &device)?;
        let mut context = Tensor::zeros((1, context_size), DType::F32, &device)?;

        // audio_sample split to chunks of size frame_size

        let chunks: Vec<Vec<f32>> = audio_sample
            .chunks(self.state.frame_size)
            .map(|chunk| chunk.to_vec())
            .collect();

        let mut filtered_count: usize = 0;

        let mut res = vec![];
        let mut pcm_res: Vec<f32> = vec![];
        for chunk_value in chunks {
            let mut chunk = chunk_value.clone();
            if chunk.len() < self.state.frame_size {
                // pad the chunk with zeros
                chunk.resize(self.state.frame_size, 0.0);
                assert_eq!(chunk.len(), self.state.frame_size);
            }
            let next_context = Tensor::from_slice(
                &chunk[self.state.frame_size - context_size..],
                (1, context_size),
                &device,
            )?;
            let chunk = Tensor::from_vec(chunk, (1, self.state.frame_size), &device)?;
            let chunk = Tensor::cat(&[&context, &chunk], 1)?;
            let inputs = std::collections::HashMap::from_iter([
                ("input".to_string(), chunk.clone()),
                ("sr".to_string(), self.state.sample_rate.clone()),
                ("state".to_string(), state.clone()),
            ]);
            let out = candle_onnx::simple_eval(&model, inputs)?;
            let out_names = &model.graph.as_ref().unwrap().output;
            let output = out.get(&out_names[0].name).unwrap().clone();
            state = out.get(&out_names[1].name).unwrap().clone();
            assert_eq!(state.dims(), &[2, 1, 128]);
            context = next_context;

            let output = output.flatten_all()?.to_vec1::<f32>()?;
            assert_eq!(output.len(), 1);
            let output = output[0];
            // println!("vad chunk prediction: {output}");
            res.push(output.clone());
            if filters_value.is_some() {
                let value = filters_value.unwrap();
                if output > value {
                    pcm_res.extend(chunk_value);
                } else {
                    // pad zero for low confidence
                    pcm_res.extend(vec![0.0; chunk_value.len()]);
                    filtered_count = filtered_count + chunk_value.len();
                }
            }
        }
        println!("VAD calculated prediction in {:?}", start.elapsed());
        let res_len = res.len() as f32;
        let prediction = res.iter().sum::<f32>() / res_len;
        // println!("vad average prediction: {prediction}");
        Ok(VadResult {
            chunk_results: res,
            pcm_results: pcm_res,
            res_len,
            prediction,
            filtered_count,
        })
    }
}

pub(crate) fn new_vad_model(model_path: String, try_with_gpu: bool) -> Result<VadDevice> {
    let device = get_device(try_with_gpu)?;
    let model = candle_onnx::read_file(model_path)?;
    let sample_rate: i64 = 16000;
    let (frame_size, context_size) = (512, 64);

    let state = VadModelState {
        frame_size,
        sample_rate: Tensor::new(sample_rate, &device)?,
    };
    let d = VadDevice {
        device,
        model,
        state,
        context_size,
    };
    Ok(d)
}
