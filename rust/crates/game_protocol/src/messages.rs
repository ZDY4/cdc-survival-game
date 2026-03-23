use game_data::{
    ActionRequest, ActionResult, ActorId, ActorKind, GridCoord, InteractionExecutionRequest,
    InteractionExecutionResult, InteractionPrompt, InteractionTargetId, TurnState, WorldCoord,
};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum ClientMessage {
    Ping,
    SubscribeWorldState,
    RequestAction(ActionRequest),
    QueryInteractionOptions {
        actor_id: ActorId,
        target_id: InteractionTargetId,
    },
    ExecuteInteraction(InteractionExecutionRequest),
    MoveActor {
        actor_id: ActorId,
        destination: WorldCoord,
    },
    FindPath {
        actor_id: Option<ActorId>,
        start: GridCoord,
        goal: GridCoord,
    },
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum ServerMessage {
    Pong,
    WorldSnapshot {
        actors: Vec<ActorSnapshot>,
        turn_state: TurnState,
    },
    ActionResult(ActionResult),
    InteractionPrompt(InteractionPrompt),
    InteractionExecution(InteractionExecutionResult),
    PathResult {
        path: Vec<GridCoord>,
    },
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ActorSnapshot {
    pub actor_id: ActorId,
    pub kind: ActorKind,
    pub position: WorldCoord,
}
