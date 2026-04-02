use std::collections::{BTreeSet, VecDeque};

use super::plan_runtime::{tick_offline_action, OfflineActionState};
use super::{ActionTickResult, NpcActionKey, NpcPlanStep};

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct NpcOfflineSimState {
    pub current_anchor: Option<String>,
    pub current_action: Option<OfflineActionState>,
    pub queued_steps: VecDeque<NpcPlanStep>,
    pub held_reservations: BTreeSet<String>,
    pub completed_actions: Vec<NpcActionKey>,
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct OfflineSimAdvanceResult {
    pub consumed_minutes: u32,
    pub finished_actions: Vec<NpcActionKey>,
    pub released_reservations: Vec<String>,
    pub current_anchor: Option<String>,
}

pub fn advance_offline_sim(
    state: &mut NpcOfflineSimState,
    mut delta_minutes: u32,
) -> OfflineSimAdvanceResult {
    let mut result = OfflineSimAdvanceResult::default();

    while state.current_action.is_some() || !state.queued_steps.is_empty() {
        if state.current_action.is_none() {
            let step = match state.queued_steps.pop_front() {
                Some(step) => step,
                None => break,
            };
            state.current_action =
                Some(OfflineActionState::new(step, state.current_anchor.clone()));
        }

        let current = match state.current_action.as_mut() {
            Some(current) => current,
            None => break,
        };

        let tick: ActionTickResult = tick_offline_action(current, delta_minutes);
        result.consumed_minutes += tick.consumed_minutes;
        if let Some(anchor) = tick.current_anchor.clone() {
            state.current_anchor = Some(anchor.clone());
            result.current_anchor = Some(anchor);
        }
        for reservation in &tick.acquired_reservations {
            state.held_reservations.insert(reservation.clone());
        }
        for reservation in &tick.released_reservations {
            state.held_reservations.remove(reservation);
            result.released_reservations.push(reservation.clone());
        }
        if let Some(action) = tick.completed_action {
            state.completed_actions.push(action.clone());
            result.finished_actions.push(action);
            state.current_action = None;
        }
        if tick.failed {
            state.current_action = None;
            break;
        }

        if delta_minutes == 0 || tick.consumed_minutes == 0 {
            break;
        }
        delta_minutes -= tick.consumed_minutes;
        if delta_minutes == 0 {
            break;
        }
    }

    result
}
