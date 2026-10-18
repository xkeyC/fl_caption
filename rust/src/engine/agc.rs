//! Automatic gain before the VAD and the recognizer.
//!
//! Quiet input (a low playback volume, a quiet recording) is boosted toward
//! a speech level the models were trained on; loud input is left alone.
//! Silero's recurrent state adapts to the level of what came before, so a
//! quiet speaker after a loud one goes unheard without this. The gain only
//! boosts (at most [`MAX_GAIN`]), falls at once when the level rises (no
//! clipping) and rises slowly, and the noise floor is never raised to the
//! target.

/// RMS of 20 ms blocks the gain aims at (about -26 dBFS).
const TARGET_RMS: f32 = 0.05;
/// +30 dB.
const MAX_GAIN: f32 = 31.6;
/// Levels below this (about -70 dBFS) count as silence: no gain is chosen
/// from them.
const FLOOR_RMS: f32 = 0.000_32;
const BLOCK: usize = 320;
/// Per block: the envelope falls ~13 dB per second, the gain rises ~13 dB
/// per second.
const ENVELOPE_RELEASE: f32 = 0.97;
const GAIN_RISE: f32 = 1.03;

#[derive(Debug, Clone)]
pub struct AutoGain {
    envelope: f32,
    gain: f32,
}

impl Default for AutoGain {
    fn default() -> Self {
        Self {
            envelope: TARGET_RMS,
            gain: 1.0,
        }
    }
}

impl AutoGain {
    pub fn gain(&self) -> f32 {
        self.gain
    }

    /// Applies the gain to `samples` in place. The gain changes per 20 ms
    /// block, ramped across the block.
    pub fn process(&mut self, samples: &mut [f32]) {
        for block in samples.chunks_mut(BLOCK) {
            let rms = (block.iter().map(|s| s * s).sum::<f32>() / block.len().max(1) as f32).sqrt();
            if rms > FLOOR_RMS {
                self.envelope = rms.max(self.envelope * ENVELOPE_RELEASE);
            }
            let wanted = (TARGET_RMS / self.envelope.max(FLOOR_RMS)).clamp(1.0, MAX_GAIN);
            let next = if wanted < self.gain {
                wanted
            } else {
                (self.gain * GAIN_RISE).min(wanted)
            };
            let step = (next - self.gain) / block.len().max(1) as f32;
            for (index, sample) in block.iter_mut().enumerate() {
                let gain = self.gain + step * (index + 1) as f32;
                *sample = (*sample * gain).clamp(-1.0, 1.0);
            }
            self.gain = next;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tone(amplitude: f32, samples: usize) -> Vec<f32> {
        (0..samples)
            .map(|i| amplitude * (i as f32 * 0.07).sin())
            .collect()
    }

    fn rms(samples: &[f32]) -> f32 {
        (samples.iter().map(|s| s * s).sum::<f32>() / samples.len() as f32).sqrt()
    }

    #[test]
    fn quiet_speech_is_raised_and_loud_left_alone() {
        let mut agc = AutoGain::default();
        let mut loud = tone(0.3, 16_000);
        agc.process(&mut loud);
        assert!((rms(&loud) - rms(&tone(0.3, 16_000))).abs() < 1e-3);
        // A -60 dBFS speaker after it: boosted within a few seconds.
        let mut quiet = tone(0.0014, 16_000 * 8);
        agc.process(&mut quiet);
        let tail = &quiet[quiet.len() - 16_000..];
        assert!(rms(tail) > 0.0014 * 20.0, "{}", rms(tail));
        assert!(agc.gain() <= MAX_GAIN);
    }

    #[test]
    fn silence_is_not_raised_to_the_target() {
        let mut agc = AutoGain::default();
        let mut hiss = tone(0.000_05, 16_000 * 10);
        agc.process(&mut hiss);
        assert!(rms(&hiss[hiss.len() - 3200..]) < 0.01);
    }
}
