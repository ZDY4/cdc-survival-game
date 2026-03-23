use std::collections::HashMap;

use game_data::{
    ActionPhase, ActionRequest, ActionType, ActorId, ActorKind, ActorSide, CharacterId, GridCoord,
};

use crate::simulation::Simulation;

#[derive(Debug, Clone)]
pub struct ActorRecord {
    pub actor_id: ActorId,
    pub definition_id: Option<CharacterId>,
    pub display_name: String,
    pub kind: ActorKind,
    pub side: ActorSide,
    pub group_id: String,
    pub registration_index: usize,
    pub ap: f32,
    pub turn_open: bool,
    pub in_combat: bool,
    pub grid_position: GridCoord,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct AiStepResult {
    pub performed: bool,
}

impl AiStepResult {
    pub const fn performed() -> Self {
        Self { performed: true }
    }

    pub const fn idle() -> Self {
        Self { performed: false }
    }
}

pub trait AiController: Send + Sync + std::fmt::Debug {
    fn execute_turn_step(&mut self, actor_id: ActorId, simulation: &mut Simulation)
        -> AiStepResult;
}

#[derive(Debug, Default)]
pub struct NoopAiController;

impl AiController for NoopAiController {
    fn execute_turn_step(
        &mut self,
        _actor_id: ActorId,
        _simulation: &mut Simulation,
    ) -> AiStepResult {
        AiStepResult::idle()
    }
}

#[derive(Debug, Default)]
pub struct InteractOnceAiController;

impl AiController for InteractOnceAiController {
    fn execute_turn_step(
        &mut self,
        actor_id: ActorId,
        simulation: &mut Simulation,
    ) -> AiStepResult {
        let start_result = simulation.request_action(ActionRequest {
            actor_id,
            action_type: ActionType::Interact,
            phase: ActionPhase::Start,
            steps: None,
            target_actor: None,
            success: true,
        });

        if !start_result.success {
            return AiStepResult::idle();
        }

        let complete_result = simulation.request_action(ActionRequest {
            actor_id,
            action_type: ActionType::Interact,
            phase: ActionPhase::Complete,
            steps: None,
            target_actor: None,
            success: true,
        });

        if complete_result.success {
            AiStepResult::performed()
        } else {
            AiStepResult::idle()
        }
    }
}

#[derive(Debug, Default)]
pub struct ActorRegistry {
    actors: HashMap<ActorId, ActorRecord>,
}

impl ActorRegistry {
    pub fn insert(&mut self, actor: ActorRecord) {
        self.actors.insert(actor.actor_id, actor);
    }

    pub fn remove(&mut self, actor_id: ActorId) -> Option<ActorRecord> {
        self.actors.remove(&actor_id)
    }

    pub fn get(&self, actor_id: ActorId) -> Option<&ActorRecord> {
        self.actors.get(&actor_id)
    }

    pub fn get_mut(&mut self, actor_id: ActorId) -> Option<&mut ActorRecord> {
        self.actors.get_mut(&actor_id)
    }

    pub fn ids(&self) -> impl Iterator<Item = ActorId> + '_ {
        self.actors.keys().copied()
    }

    pub fn values(&self) -> impl Iterator<Item = &ActorRecord> {
        self.actors.values()
    }

    pub fn contains(&self, actor_id: ActorId) -> bool {
        self.actors.contains_key(&actor_id)
    }
}
