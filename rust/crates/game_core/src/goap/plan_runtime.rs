use super::{NpcActionKey, NpcPlanStep};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ActionExecutionPhase {
    AcquireReservation,
    Travel,
    Perform,
    ReleaseReservation,
    Complete,
    Failed,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct OfflineActionState {
    pub step: NpcPlanStep,
    pub phase: ActionExecutionPhase,
    pub travel_remaining_minutes: u32,
    pub perform_remaining_minutes: u32,
    pub current_anchor: Option<String>,
}

impl OfflineActionState {
    pub fn new(step: NpcPlanStep, current_anchor: Option<String>) -> Self {
        Self {
            travel_remaining_minutes: step.travel_minutes,
            perform_remaining_minutes: step.perform_minutes,
            step,
            phase: ActionExecutionPhase::AcquireReservation,
            current_anchor,
        }
    }

    pub fn advance_after_acquire(&mut self) {
        if self.phase == ActionExecutionPhase::AcquireReservation {
            self.phase = ActionExecutionPhase::Travel;
        }
    }

    pub fn fail(&mut self) {
        self.phase = ActionExecutionPhase::Failed;
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct ActionTickResult {
    pub finished: bool,
    pub failed: bool,
    pub consumed_minutes: u32,
    pub released_reservations: Vec<String>,
    pub acquired_reservations: Vec<String>,
    pub current_anchor: Option<String>,
    pub completed_action: Option<NpcActionKey>,
}

pub fn tick_offline_action(state: &mut OfflineActionState, delta_minutes: u32) -> ActionTickResult {
    let mut result = ActionTickResult::default();
    let mut remaining = delta_minutes;

    loop {
        match state.phase {
            ActionExecutionPhase::AcquireReservation => {
                if let Some(target) = &state.step.reservation_target {
                    result.acquired_reservations.push(target.clone());
                }
                state.phase = ActionExecutionPhase::Travel;
            }
            ActionExecutionPhase::Travel => {
                if state.travel_remaining_minutes == 0 {
                    state.current_anchor = state
                        .step
                        .target_anchor
                        .clone()
                        .or_else(|| state.current_anchor.clone());
                    result.current_anchor = state.current_anchor.clone();
                    state.phase = ActionExecutionPhase::Perform;
                    continue;
                }
                if remaining == 0 {
                    break;
                }
                let spent = state.travel_remaining_minutes.min(remaining);
                state.travel_remaining_minutes -= spent;
                remaining -= spent;
                result.consumed_minutes += spent;
            }
            ActionExecutionPhase::Perform => {
                if state.perform_remaining_minutes == 0 {
                    state.phase = ActionExecutionPhase::ReleaseReservation;
                    continue;
                }
                if remaining == 0 {
                    break;
                }
                let spent = state.perform_remaining_minutes.min(remaining);
                state.perform_remaining_minutes -= spent;
                remaining -= spent;
                result.consumed_minutes += spent;
            }
            ActionExecutionPhase::ReleaseReservation => {
                if let Some(target) = &state.step.reservation_target {
                    result.released_reservations.push(target.clone());
                }
                state.phase = ActionExecutionPhase::Complete;
            }
            ActionExecutionPhase::Complete => {
                result.finished = true;
                result.current_anchor = state.current_anchor.clone();
                result.completed_action = Some(state.step.action);
                break;
            }
            ActionExecutionPhase::Failed => {
                result.failed = true;
                break;
            }
        }
    }

    result
}
