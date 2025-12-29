//! FSRS Swift - FSRS v6 spaced repetition scheduler with UniFFI bindings
//!
//! Wraps the fsrs-rs crate for use in Swift via UniFFI.

use fsrs::{FSRS, MemoryState as InternalMemoryState, NextStates as InternalNextStates};

uniffi::setup_scaffolding!();

/// User rating for a card review
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum Rating {
    Again = 1,
    Hard = 2,
    Good = 3,
    Easy = 4,
}

/// Memory state of a card (replaces SM-2's easeFactor/interval/repetitions)
#[derive(Debug, Clone, Copy, uniffi::Record)]
pub struct MemoryState {
    /// Stability: expected time (in days) to reach 90% recall probability
    pub stability: f32,
    /// Difficulty: inherent difficulty of the card (0.0 - 1.0)
    pub difficulty: f32,
}

impl From<InternalMemoryState> for MemoryState {
    fn from(m: InternalMemoryState) -> Self {
        Self {
            stability: m.stability,
            difficulty: m.difficulty,
        }
    }
}

impl From<MemoryState> for InternalMemoryState {
    fn from(m: MemoryState) -> Self {
        Self {
            stability: m.stability,
            difficulty: m.difficulty,
        }
    }
}

/// Scheduling information for a single rating option
#[derive(Debug, Clone, Copy, uniffi::Record)]
pub struct SchedulingInfo {
    /// Updated memory state after the review
    pub memory: MemoryState,
    /// Days until next review (rounded from float)
    pub interval: u32,
}

/// All possible next states for each rating option
#[derive(Debug, Clone, uniffi::Record)]
pub struct NextStates {
    pub again: SchedulingInfo,
    pub hard: SchedulingInfo,
    pub good: SchedulingInfo,
    pub easy: SchedulingInfo,
}

impl From<InternalNextStates> for NextStates {
    fn from(ns: InternalNextStates) -> Self {
        Self {
            again: SchedulingInfo {
                memory: ns.again.memory.into(),
                // Round to nearest day, minimum 0 (same day)
                interval: ns.again.interval.round() as u32,
            },
            hard: SchedulingInfo {
                memory: ns.hard.memory.into(),
                interval: ns.hard.interval.round().max(1.0) as u32,
            },
            good: SchedulingInfo {
                memory: ns.good.memory.into(),
                interval: ns.good.interval.round().max(1.0) as u32,
            },
            easy: SchedulingInfo {
                memory: ns.easy.memory.into(),
                interval: ns.easy.interval.round().max(1.0) as u32,
            },
        }
    }
}

/// Error types for FSRS operations
#[derive(Debug, Clone, thiserror::Error, uniffi::Error)]
pub enum FSRSError {
    #[error("Invalid parameters: {message}")]
    InvalidParameters { message: String },
    #[error("Computation error: {message}")]
    ComputationError { message: String },
}

/// Calculate next states for all rating options
///
/// # Arguments
/// * `memory` - Current memory state (None for new card)
/// * `desired_retention` - Target retention probability (0.7-0.99, typically 0.9)
/// * `days_elapsed` - Days since last review (0 for new card)
///
/// # Returns
/// * `NextStates` containing scheduling info for each rating option (Again, Hard, Good, Easy)
#[uniffi::export]
pub fn next_states(
    memory: Option<MemoryState>,
    desired_retention: f32,
    days_elapsed: u32,
) -> Result<NextStates, FSRSError> {
    let fsrs = FSRS::new(Some(&[])).map_err(|e| FSRSError::InvalidParameters {
        message: e.to_string(),
    })?;

    let internal_memory = memory.map(InternalMemoryState::from);

    let states = fsrs
        .next_states(internal_memory, desired_retention, days_elapsed)
        .map_err(|e| FSRSError::ComputationError {
            message: e.to_string(),
        })?;

    Ok(states.into())
}

/// Schedule a card review with a specific rating
///
/// Convenience function that calls next_states and returns only the result for the given rating.
#[uniffi::export]
pub fn schedule(
    memory: Option<MemoryState>,
    rating: Rating,
    desired_retention: f32,
    days_elapsed: u32,
) -> Result<SchedulingInfo, FSRSError> {
    let states = next_states(memory, desired_retention, days_elapsed)?;

    Ok(match rating {
        Rating::Again => states.again,
        Rating::Hard => states.hard,
        Rating::Good => states.good,
        Rating::Easy => states.easy,
    })
}

/// Calculate current retrievability (recall probability)
///
/// # Arguments
/// * `stability` - Current stability value from memory state
/// * `days_elapsed` - Days since last review
///
/// # Returns
/// * Probability of recall (0.0 - 1.0)
#[uniffi::export]
pub fn current_retrievability(stability: f32, days_elapsed: u32) -> f32 {
    if stability <= 0.0 {
        return 0.0;
    }
    // FSRS retrievability formula: R = (1 + days/S * c)^(-1/decay)
    // Using FSRS-5 default decay of 0.5 for now
    let decay = 0.5_f32;
    let factor = 19.0_f32 / 81.0_f32; // c = 19/81 for FSRS-5
    (1.0 + (days_elapsed as f32) / stability * factor).powf(-1.0 / decay)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_new_card_scheduling() {
        let states = next_states(None, 0.9, 0).unwrap();
        // New card should have short intervals
        assert!(states.again.interval >= 1);
        assert!(states.good.interval >= 1);
        // Easy should have longest interval
        assert!(states.easy.interval >= states.good.interval);
    }

    #[test]
    fn test_review_card_scheduling() {
        // Simulate a card with some memory state
        let memory = MemoryState {
            stability: 10.0,
            difficulty: 0.3,
        };

        let states = next_states(Some(memory), 0.9, 5).unwrap();
        // Should have increasing intervals
        assert!(states.again.interval < states.hard.interval);
        assert!(states.hard.interval <= states.good.interval);
        assert!(states.good.interval <= states.easy.interval);
    }

    #[test]
    fn test_schedule_single_rating() {
        let info = schedule(None, Rating::Good, 0.9, 0).unwrap();
        assert!(info.interval >= 1);
        assert!(info.memory.stability > 0.0);
    }

    #[test]
    fn test_retrievability() {
        // At day 0, retrievability should be ~1.0
        let r0 = current_retrievability(10.0, 0);
        assert!((r0 - 1.0).abs() < 0.01);

        // As days increase, retrievability decreases
        let r5 = current_retrievability(10.0, 5);
        assert!(r5 < r0);

        let r10 = current_retrievability(10.0, 10);
        assert!(r10 < r5);
    }

    #[test]
    fn test_retrievability_edge_cases() {
        // Zero stability should return 0
        assert_eq!(current_retrievability(0.0, 5), 0.0);
        assert_eq!(current_retrievability(-1.0, 5), 0.0);
    }
}

#[cfg(test)]
mod integration_tests {
    use super::*;

    #[test]
    fn test_print_new_card_scheduling() {
        println!("\n=== NEW CARD (first review) ===");
        let states = next_states(None, 0.9, 0).unwrap();
        
        println!("Again: {} day(s), stability={:.2}, difficulty={:.2}", 
            states.again.interval, states.again.memory.stability, states.again.memory.difficulty);
        println!("Hard:  {} day(s), stability={:.2}, difficulty={:.2}", 
            states.hard.interval, states.hard.memory.stability, states.hard.memory.difficulty);
        println!("Good:  {} day(s), stability={:.2}, difficulty={:.2}", 
            states.good.interval, states.good.memory.stability, states.good.memory.difficulty);
        println!("Easy:  {} day(s), stability={:.2}, difficulty={:.2}", 
            states.easy.interval, states.easy.memory.stability, states.easy.memory.difficulty);
    }

    #[test]
    fn test_print_review_progression() {
        println!("\n=== CARD REVIEW PROGRESSION (always rating Good) ===");
        
        let mut memory: Option<MemoryState> = None;
        let retention = 0.9;
        
        for review_num in 1..=6 {
            let states = next_states(memory, retention, 0).unwrap();
            let info = states.good;
            
            println!("Review {}: interval={} day(s), stability={:.1}, difficulty={:.2}",
                review_num, info.interval, info.memory.stability, info.memory.difficulty);
            
            memory = Some(info.memory);
        }
    }

    #[test]
    fn test_print_retrievability_decay() {
        println!("\n=== RETRIEVABILITY DECAY (stability=10 days) ===");
        let stability = 10.0;
        
        for days in [0, 1, 3, 5, 7, 10, 14, 21, 30] {
            let r = current_retrievability(stability, days);
            println!("Day {:2}: {:.0}% recall probability", days, r * 100.0);
        }
    }
}

#[cfg(test)]
mod raw_interval_test {
    use super::*;
    use fsrs::FSRS;

    #[test]
    fn test_raw_fsrs_intervals() {
        println!("\n=== RAW FSRS INTERVALS (in days) ===");
        let fsrs = FSRS::new(Some(&[])).unwrap();
        let states = fsrs.next_states(None, 0.9, 0).unwrap();
        
        println!("Again: {:.4} days = {:.1} minutes", states.again.interval, states.again.interval * 24.0 * 60.0);
        println!("Hard:  {:.4} days = {:.1} minutes", states.hard.interval, states.hard.interval * 24.0 * 60.0);
        println!("Good:  {:.4} days = {:.1} minutes", states.good.interval, states.good.interval * 24.0 * 60.0);
        println!("Easy:  {:.4} days = {:.1} minutes", states.easy.interval, states.easy.interval * 24.0 * 60.0);
    }
}
