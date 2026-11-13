//! IMA ADPCM decoder for KiwiSDR compressed audio streams. Port of
//! `KiwiSDRADPCM.swift`. KiwiSDR uses IMA ADPCM (4:1) for mono audio modes;
//! each input byte yields two samples, low nibble first.

const STEP_TABLE: [i32; 89] = [
    7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 21, 23, 25, 28, 31, 34, 37, 41, 45, 50, 55, 60, 66,
    73, 80, 88, 97, 107, 118, 130, 143, 157, 173, 190, 209, 230, 253, 279, 307, 337, 371, 408,
    449, 494, 544, 598, 658, 724, 796, 876, 963, 1_060, 1_166, 1_282, 1_411, 1_552, 1_707, 1_878,
    2_066, 2_272, 2_499, 2_749, 3_024, 3_327, 3_660, 4_026, 4_428, 4_871, 5_358, 5_894, 6_484,
    7_132, 7_845, 8_630, 9_493, 10_442, 11_487, 12_635, 13_899, 15_289, 16_818, 18_500, 20_350,
    22_385, 24_623, 27_086, 29_794, 32_767,
];

const INDEX_TABLE: [i32; 16] = [-1, -1, -1, -1, 2, 4, 6, 8, -1, -1, -1, -1, 2, 4, 6, 8];

/// Mutable decoder state carried between frames. The server can reset it
/// mid-stream via a `MSG audio_adpcm_state=` message.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct AdpcmState {
    pub predictor: i32,
    pub step_index: i32,
}

impl AdpcmState {
    /// Apply a server-sent state reset (`audio_adpcm_state=index,predictor`).
    /// The index is clamped to the valid step-table range like the Swift port.
    pub fn reset(&mut self, step_index: i32, predictor: i32) {
        self.step_index = step_index.clamp(0, 88);
        self.predictor = predictor;
    }
}

/// Decode IMA ADPCM bytes to Int16 PCM samples. Each byte produces two output
/// samples (4 bits per sample), low nibble first.
pub fn decode(data: &[u8], state: &mut AdpcmState) -> Vec<i16> {
    let mut samples = Vec::with_capacity(data.len() * 2);
    for &byte in data {
        samples.push(decode_nibble(byte & 0x0F, state));
        samples.push(decode_nibble(byte >> 4, state));
    }
    samples
}

fn decode_nibble(nibble: u8, state: &mut AdpcmState) -> i16 {
    let step = STEP_TABLE[state.step_index as usize];

    state.step_index = (state.step_index + INDEX_TABLE[nibble as usize]).clamp(0, 88);

    let mut diff = step >> 3;
    if nibble & 4 != 0 {
        diff += step;
    }
    if nibble & 2 != 0 {
        diff += step >> 1;
    }
    if nibble & 1 != 0 {
        diff += step >> 2;
    }

    if nibble & 8 != 0 {
        state.predictor -= diff;
    } else {
        state.predictor += diff;
    }

    state.predictor = state.predictor.clamp(-32_768, 32_767);
    state.predictor as i16
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn each_byte_yields_two_samples() {
        let mut state = AdpcmState::default();
        let samples = decode(&[0x00, 0xFF, 0x7A], &mut state);
        assert_eq!(samples.len(), 6);
    }

    /// Parity fixture: decoding a known byte sequence from zeroed state must
    /// match the Swift decoder sample-for-sample (hand-executed against the
    /// shared IMA ADPCM tables):
    ///   0x17 low nibble 7:  step 7,  diff 0+7+3+1 = 11 → predictor 11,  index 0+8 = 8
    ///   0x17 high nibble 1: step 16, diff 2+4     = 6  → predictor 17,  index 8-1 = 7
    ///   0x9C low nibble 12: step 14, diff 1+14    = 15 → predictor 2,   index 7+2 = 9 (sign)
    ///   0x9C high nibble 9: step 17, diff 2+4     = 6  → predictor -4,  index 9-1 = 8 (sign)
    #[test]
    fn known_sequence_parity() {
        let mut state = AdpcmState::default();
        let samples = decode(&[0x17, 0x9C], &mut state);
        assert_eq!(samples, vec![11, 17, 2, -4]);
        assert_eq!(state.predictor, -4);
        assert_eq!(state.step_index, 8);
    }

    #[test]
    fn predictor_clamps_to_int16_range() {
        let mut state = AdpcmState { predictor: 32_700, step_index: 88 };
        let samples = decode(&[0x77, 0x77], &mut state);
        assert!(samples.iter().all(|&sample| sample == 32_767));

        let mut state = AdpcmState { predictor: -32_700, step_index: 88 };
        let samples = decode(&[0xFF, 0xFF], &mut state);
        assert!(samples.iter().all(|&sample| sample == -32_768));
    }

    #[test]
    fn state_reset_clamps_index() {
        let mut state = AdpcmState::default();
        state.reset(200, 123);
        assert_eq!(state.step_index, 88);
        assert_eq!(state.predictor, 123);
        state.reset(-5, 0);
        assert_eq!(state.step_index, 0);
    }
}
