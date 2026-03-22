use game_data::{
    ActionRequest, ActionResult, ActorId, ActorKind, GridCoord, TurnState, WorldCoord,
};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum ClientMessage {
    Ping,
    SubscribeWorldState,
    RequestAction(ActionRequest),
    MoveActor { actor_id: ActorId, destination: WorldCoord },
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
    PathResult { path: Vec<GridCoord> },
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ActorSnapshot {
    pub actor_id: ActorId,
    pub kind: ActorKind,
    pub position: WorldCoord,
}
