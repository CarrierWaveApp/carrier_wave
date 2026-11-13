//! dB → 0..1 normalization for the waterfall color map, with an optional
//! auto-tracked noise floor.

/// Percentile of the line treated as the noise floor.
const FLOOR_PERCENTILE: f32 = 0.2;
/// EMA weight for a new floor estimate (~1 s time constant at 25 fps).
const FLOOR_SMOOTHING: f32 = 0.05;
/// The floor maps slightly above 0 so noise texture stays visible.
const FLOOR_HEADROOM_DB: f32 = 6.0;

pub struct Normalizer {
    auto_floor: bool,
    floor_db: f32,
    range_db: f32,
    tracked: Option<f32>,
}

impl Normalizer {
    pub fn new(auto_floor: bool, floor_db: f32, range_db: f32) -> Self {
        Normalizer { auto_floor, floor_db, range_db: range_db.max(1.0), tracked: None }
    }

    /// Normalize one dB line. Non-finite values (outside the SDR passband)
    /// map to 0. Returns the values and the floor (dB) that was used.
    pub fn process(&mut self, line_db: &[f32]) -> (Vec<f32>, f32) {
        let floor = if self.auto_floor { self.track_floor(line_db) } else { self.floor_db };
        let base = floor - FLOOR_HEADROOM_DB;
        let values = line_db
            .iter()
            .map(|db| if db.is_finite() { ((db - base) / self.range_db).clamp(0.0, 1.0) } else { 0.0 })
            .collect();
        (values, floor)
    }

    fn track_floor(&mut self, line_db: &[f32]) -> f32 {
        let mut finite: Vec<f32> = line_db.iter().copied().filter(|db| db.is_finite()).collect();
        if finite.is_empty() {
            return self.tracked.unwrap_or(self.floor_db);
        }
        let index = ((finite.len() - 1) as f32 * FLOOR_PERCENTILE) as usize;
        let (_, estimate, _) = finite.select_nth_unstable_by(index, f32::total_cmp);
        let estimate = *estimate;
        let floor = match self.tracked {
            Some(prev) => prev + FLOOR_SMOOTHING * (estimate - prev),
            None => estimate,
        };
        self.tracked = Some(floor);
        floor
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn fixed_floor_maps_range() {
        let mut norm = Normalizer::new(false, -100.0, 60.0);
        let (values, floor) = norm.process(&[-106.0, -76.0, -46.0, -10.0, f32::NEG_INFINITY]);
        assert_eq!(floor, -100.0);
        assert_eq!(values, vec![0.0, 0.5, 1.0, 1.0, 0.0]);
    }

    #[test]
    fn auto_floor_tracks_noise_percentile() {
        let mut norm = Normalizer::new(true, -100.0, 60.0);
        let mut line = vec![-90.0f32; 100];
        line[50] = -30.0;
        let (_, floor) = norm.process(&line);
        assert_eq!(floor, -90.0);
        // Floor moves slowly toward a new estimate.
        let (_, next) = norm.process(&vec![-70.0f32; 100]);
        assert!(next > -90.0 && next < -88.0);
    }
}
