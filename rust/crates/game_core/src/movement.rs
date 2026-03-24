use std::error::Error;
use std::fmt;

use game_data::{ActionResult, ActorId, GridCoord, InteractionTargetId, WorldCoord};

use crate::grid::{GridPathfindingError, GridWorld};

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum MovementPlanError {
    UnknownActor { actor_id: ActorId },
    ActorNotPlayerControlled,
    InputNotAllowed,
    TargetOutOfBounds,
    TargetInvalidLevel,
    TargetBlocked,
    TargetOccupied,
    NoPath,
}

impl fmt::Display for MovementPlanError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::UnknownActor { actor_id } => write!(f, "unknown actor: {:?}", actor_id),
            Self::ActorNotPlayerControlled => write!(f, "actor is not player controlled"),
            Self::InputNotAllowed => write!(f, "actor input is not allowed"),
            Self::TargetOutOfBounds => write!(f, "target out of bounds"),
            Self::TargetInvalidLevel => write!(f, "target level is not available"),
            Self::TargetBlocked => write!(f, "target blocked"),
            Self::TargetOccupied => write!(f, "target occupied"),
            Self::NoPath => write!(f, "no path"),
        }
    }
}

impl Error for MovementPlanError {}

impl From<GridPathfindingError> for MovementPlanError {
    fn from(value: GridPathfindingError) -> Self {
        match value {
            GridPathfindingError::TargetOutOfBounds => Self::TargetOutOfBounds,
            GridPathfindingError::TargetInvalidLevel => Self::TargetInvalidLevel,
            GridPathfindingError::TargetBlocked => Self::TargetBlocked,
            GridPathfindingError::TargetOccupied => Self::TargetOccupied,
            GridPathfindingError::NoPath => Self::NoPath,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MovementPlan {
    pub actor_id: ActorId,
    pub start: GridCoord,
    pub requested_goal: GridCoord,
    pub requested_path: Vec<GridCoord>,
    pub resolved_goal: GridCoord,
    pub resolved_path: Vec<GridCoord>,
    pub available_steps: usize,
}

impl MovementPlan {
    pub fn requested_steps(&self) -> usize {
        self.requested_path.len().saturating_sub(1)
    }

    pub fn resolved_steps(&self) -> usize {
        self.resolved_path.len().saturating_sub(1)
    }

    pub fn is_truncated(&self) -> bool {
        self.requested_goal != self.resolved_goal || self.requested_path != self.resolved_path
    }

    pub fn requested_world_path(&self, world: &GridWorld) -> Vec<WorldCoord> {
        self.requested_path
            .iter()
            .copied()
            .skip(1)
            .map(|grid| world.grid_to_world(grid))
            .collect()
    }

    pub fn resolved_world_path(&self, world: &GridWorld) -> Vec<WorldCoord> {
        self.resolved_path
            .iter()
            .copied()
            .skip(1)
            .map(|grid| world.grid_to_world(grid))
            .collect()
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct MovementCommandOutcome {
    pub plan: MovementPlan,
    pub result: ActionResult,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct PendingMovementIntent {
    pub actor_id: ActorId,
    pub requested_goal: GridCoord,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PendingInteractionIntent {
    pub actor_id: ActorId,
    pub target_id: InteractionTargetId,
    pub option_id: String,
    pub approach_goal: GridCoord,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PendingProgressionStep {
    EndCurrentCombatTurn,
    RunNonCombatWorldCycle,
    StartNextNonCombatPlayerTurn,
    ContinuePendingMovement,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AutoMoveInterruptReason {
    ReachedGoal,
    EnteredCombat,
    ActorNotPlayerControlled,
    InputNotAllowed,
    TargetOutOfBounds,
    TargetInvalidLevel,
    TargetBlocked,
    TargetOccupied,
    NoPath,
    NoProgress,
    CancelledByNewCommand,
    UnknownActor,
}

#[derive(Debug, Clone, PartialEq)]
pub struct ProgressionAdvanceResult {
    pub applied_step: Option<PendingProgressionStep>,
    pub final_position: Option<GridCoord>,
    pub reached_goal: bool,
    pub interrupted: bool,
    pub interrupt_reason: Option<AutoMoveInterruptReason>,
    pub movement_outcome: Option<MovementCommandOutcome>,
}

impl ProgressionAdvanceResult {
    pub fn idle(final_position: Option<GridCoord>) -> Self {
        Self {
            applied_step: None,
            final_position,
            reached_goal: false,
            interrupted: false,
            interrupt_reason: None,
            movement_outcome: None,
        }
    }

    pub fn applied(step: PendingProgressionStep, final_position: Option<GridCoord>) -> Self {
        Self {
            applied_step: Some(step),
            final_position,
            reached_goal: false,
            interrupted: false,
            interrupt_reason: None,
            movement_outcome: None,
        }
    }
}
