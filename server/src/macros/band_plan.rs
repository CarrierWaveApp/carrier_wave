//! Band-plan validation for `RadioMacroArg.frequency` arg bounds (CAR-271 T4).
//!
//! When a macro accepts a frequency arg, the editor and admin sync must
//! demand `min` and `max` values. The verifier already enforces *presence*
//! ([`super::verifier`] emits "Frequency arg '...' must declare min/max
//! bounds"); this module adds the **plausibility** check: bounds must lie
//! in plausible ham ranges and `min < max`.

use crate::macros::spec::{ArgType, RadioMacroArg};

/// Lower bound — covers 472 kHz (630 m) plus a margin for sub-band macros.
const MIN_PLAUSIBLE_HZ: i64 = 100_000;
/// Upper bound — covers up to 250 GHz (mm-wave amateur allocations).
const MAX_PLAUSIBLE_HZ: i64 = 250_000_000_000;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BandPlanError {
    MissingBounds { arg: String },
    InvertedBounds { arg: String, min: i64, max: i64 },
    OutOfRange { arg: String, value: i64 },
}

impl std::fmt::Display for BandPlanError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::MissingBounds { arg } => {
                write!(f, "frequency arg `{arg}` requires min and max bounds")
            }
            Self::InvertedBounds { arg, min, max } => write!(
                f,
                "frequency arg `{arg}` must have min < max (got min={min}, max={max})"
            ),
            Self::OutOfRange { arg, value } => write!(
                f,
                "frequency arg `{arg}` value {value} Hz lies outside plausible ham ranges \
                 ({MIN_PLAUSIBLE_HZ}..={MAX_PLAUSIBLE_HZ})"
            ),
        }
    }
}

impl std::error::Error for BandPlanError {}

/// Validate every frequency arg's `min`/`max` against the plausibility
/// rules. Non-frequency args pass through.
pub fn validate(args: &[RadioMacroArg]) -> Result<(), BandPlanError> {
    for arg in args {
        if arg.arg_type != ArgType::Frequency {
            continue;
        }
        let (Some(min), Some(max)) = (arg.min, arg.max) else {
            return Err(BandPlanError::MissingBounds {
                arg: arg.name.clone(),
            });
        };
        if min >= max {
            return Err(BandPlanError::InvertedBounds {
                arg: arg.name.clone(),
                min,
                max,
            });
        }
        if !(MIN_PLAUSIBLE_HZ..=MAX_PLAUSIBLE_HZ).contains(&min)
            || !(MIN_PLAUSIBLE_HZ..=MAX_PLAUSIBLE_HZ).contains(&max)
        {
            let value = if (MIN_PLAUSIBLE_HZ..=MAX_PLAUSIBLE_HZ).contains(&min) {
                max
            } else {
                min
            };
            return Err(BandPlanError::OutOfRange {
                arg: arg.name.clone(),
                value,
            });
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn freq_arg(name: &str, min: Option<i64>, max: Option<i64>) -> RadioMacroArg {
        RadioMacroArg {
            name: name.to_string(),
            arg_type: ArgType::Frequency,
            min,
            max,
        }
    }

    fn int_arg(name: &str) -> RadioMacroArg {
        RadioMacroArg {
            name: name.to_string(),
            arg_type: ArgType::Integer,
            min: None,
            max: None,
        }
    }

    #[test]
    fn forty_meter_band_plan() {
        validate(&[freq_arg("f", Some(7_000_000), Some(7_300_000))]).unwrap();
    }

    #[test]
    fn missing_min_rejected() {
        let err = validate(&[freq_arg("f", None, Some(7_300_000))]).unwrap_err();
        assert!(matches!(err, BandPlanError::MissingBounds { .. }));
    }

    #[test]
    fn inverted_bounds_rejected() {
        let err = validate(&[freq_arg("f", Some(7_300_000), Some(7_000_000))]).unwrap_err();
        assert!(matches!(err, BandPlanError::InvertedBounds { .. }));
    }

    #[test]
    fn zero_min_out_of_range() {
        let err = validate(&[freq_arg("f", Some(0), Some(7_300_000))]).unwrap_err();
        assert!(matches!(err, BandPlanError::OutOfRange { .. }));
    }

    #[test]
    fn non_frequency_args_pass_through() {
        validate(&[int_arg("count")]).unwrap();
    }

    #[test]
    fn extreme_high_band_passes() {
        // 24 GHz (12 mm band)
        validate(&[freq_arg("f", Some(24_000_000_000), Some(24_250_000_000))]).unwrap();
    }
}
