use anyhow::Result;
use ndarray::{Array1, Array2, Array3, Axis};
use ort::{inputs, session::Session, value::Tensor};

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
            let full_chunk_vec: Vec<f32> = full_chunk.iter().cloned().collect();

            let sr_array = Array1::<i64>::from_elem(1, self.state.sample_rate);
            let state_vec: Vec<f32> = state.iter().cloned().collect();

            let input_value =
                Tensor::from_array(([1, full_chunk.len()], full_chunk_vec.into_boxed_slice()))?;
            let sr_value = Tensor::from_array(([1], sr_array.to_vec().into_boxed_slice()))?;
            let state_value = Tensor::from_array(([2, 1, 128], state_vec.into_boxed_slice()))?;

            let outputs = self.session.run(inputs![
                "input" => input_value,
                "sr" => sr_value,
                "state" => state_value
            ])?;

            let output_keys: Vec<_> = outputs.keys().collect();
            if output_keys.len() < 2 {
                return Err(anyhow::anyhow!(
                    "Expected at least 2 outputs, got {}",
                    output_keys.len()
                ));
            }

            let output = outputs.get(&output_keys[0]).unwrap();
            let new_state = outputs.get(&output_keys[1]).unwrap();

            let output_tensor = output.try_extract_tensor::<f32>()?;
            let state_tensor = new_state.try_extract_tensor::<f32>()?;

            let prediction_value = output_tensor.1[0];
            res.push(prediction_value);

            let state_data: Vec<f32> = state_tensor.1.iter().cloned().collect();
            state = Array3::<f32>::from_shape_vec((2, 1, 128), state_data)?;
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
    let session = Session::builder()?.commit_from_file(model_path)?;

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
