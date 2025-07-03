use anyhow::Result;
use ndarray::{Array1, Array2, Array3, Axis};
use ort::{inputs, session::Session, value::Value};

struct VadModelState {
    frame_size: usize,
    sample_rate: i64,
}

pub struct VadDevice {
    session: Session,
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
        &mut self,
        audio_sample: Vec<f32>,
        filters_value: Option<f32>,
    ) -> Result<VadResult> {
        let start = std::time::Instant::now();
        let context_size = self.context_size;

        let mut state = Array3::<f32>::zeros((2, 1, 128));
        let mut context = Array2::<f32>::zeros((1, context_size));

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
                chunk.resize(self.state.frame_size, 0.0);
                assert_eq!(chunk.len(), self.state.frame_size);
            }

            let next_context_data = &chunk[self.state.frame_size - context_size..];
            let mut next_context = Array2::<f32>::zeros((1, context_size));
            for (i, &val) in next_context_data.iter().enumerate() {
                next_context[[0, i]] = val;
            }

            let mut chunk_array = Array2::<f32>::zeros((1, self.state.frame_size));
            for (i, &val) in chunk.iter().enumerate() {
                chunk_array[[0, i]] = val;
            }

            let full_chunk = ndarray::concatenate![Axis(1), context, chunk_array];

            let sr_array = Array1::<i64>::from_elem(1, self.state.sample_rate);

            let outputs = self.session.run(inputs![
                "input" => Value::from_array(full_chunk)?,
                "sr" => Value::from_array(sr_array)?,
                "state" => Value::from_array(state.clone())?
            ])?;

            let output_keys: Vec<_> = outputs.keys().collect();
            if output_keys.len() < 2 {
                return Err(anyhow::anyhow!("Expected at least 2 outputs, got {}", output_keys.len()));
            }

            let output = outputs.get(&output_keys[0]).unwrap();
            let new_state = outputs.get(&output_keys[1]).unwrap();

            let output_tensor = output.try_extract_tensor::<f32>()?;
            let state_tensor = new_state.try_extract_tensor::<f32>()?;

            let prediction_value = output_tensor.1[0]; // 获取第一个值
            res.push(prediction_value);

            state = Array3::<f32>::from_shape_vec((2, 1, 128), state_tensor.1.to_vec())?;
            context = next_context;

            if let Some(value) = filters_value {
                if prediction_value > value {
                    pcm_res.extend(chunk_value);
                } else {
                    pcm_res.extend(vec![0.0; chunk_value.len()]);
                    filtered_count += chunk_value.len();
                }
            }
        }

        println!("VAD calculated prediction in {:?}", start.elapsed());
        let res_len = res.len() as f32;
        let prediction = res.iter().sum::<f32>() / res_len;

        Ok(VadResult {
            chunk_results: res,
            pcm_results: pcm_res,
            res_len,
            prediction,
            filtered_count,
        })
    }
}

pub fn new_vad_model(model_path: String, _try_with_gpu: bool) -> Result<VadDevice> {
    let session = Session::builder()?
        .commit_from_file(model_path)?;

    let sample_rate: i64 = 16000;
    let (frame_size, context_size) = (512, 64);

    let state = VadModelState {
        frame_size,
        sample_rate,
    };

    let device = VadDevice {
        session,
        state,
        context_size,
    };

    Ok(device)
}
