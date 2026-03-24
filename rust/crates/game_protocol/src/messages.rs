use game_data::{
    ActionRequest, ActionResult, ActorId, ActorKind, GridCoord, InteractionContextSnapshot,
    InteractionExecutionRequest, InteractionExecutionResult, InteractionPrompt,
    InteractionTargetId, TurnState, WorldCoord,
};
use serde::{Deserialize, Serialize};
use serde_json::Value;

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct RuntimeSubscriptionRequest {
    #[serde(default)]
    pub include_deltas: bool,
    #[serde(default = "default_true")]
    pub include_snapshots: bool,
    #[serde(default)]
    pub include_debug_state: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct DialogueAdvanceRequest {
    pub actor_id: ActorId,
    #[serde(default)]
    pub target_id: Option<InteractionTargetId>,
    #[serde(default)]
    pub dialogue_id: String,
    #[serde(default)]
    pub option_id: Option<String>,
    #[serde(default)]
    pub option_index: Option<usize>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct MapTravelRequest {
    pub actor_id: ActorId,
    #[serde(default)]
    pub target_map_id: String,
    #[serde(default)]
    pub entry_point: Option<String>,
    #[serde(default)]
    pub world_mode: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct WorldSnapshotEnvelope {
    #[serde(default)]
    pub sequence: u64,
    #[serde(default)]
    pub actors: Vec<ActorSnapshot>,
    #[serde(default)]
    pub turn_state: TurnState,
    #[serde(default)]
    pub interaction_context: Option<InteractionContextSnapshot>,
    #[serde(default)]
    pub active_map_id: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct RuntimeEventEnvelope {
    #[serde(default)]
    pub sequence: u64,
    #[serde(default)]
    pub event_type: String,
    #[serde(default)]
    pub actor_id: Option<ActorId>,
    #[serde(default)]
    pub target_id: Option<InteractionTargetId>,
    #[serde(default)]
    pub dialogue_id: Option<String>,
    #[serde(default)]
    pub map_id: Option<String>,
    #[serde(default)]
    pub payload: Value,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct SceneTransitionNotice {
    pub actor_id: ActorId,
    #[serde(default)]
    pub target_map_id: String,
    #[serde(default)]
    pub entry_point: Option<String>,
    #[serde(default)]
    pub world_mode: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct ProtocolError {
    #[serde(default)]
    pub code: String,
    #[serde(default)]
    pub message: String,
    #[serde(default)]
    pub retryable: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum ClientMessage {
    Ping,
    SubscribeWorldState,
    Handshake {
        protocol_version: u32,
    },
    SubscribeRuntime(RuntimeSubscriptionRequest),
    RequestWorldSnapshot,
    RequestAction(ActionRequest),
    QueryInteractionOptions {
        actor_id: ActorId,
        target_id: InteractionTargetId,
    },
    ExecuteInteraction(InteractionExecutionRequest),
    AdvanceDialogue(DialogueAdvanceRequest),
    MoveActor {
        actor_id: ActorId,
        destination: WorldCoord,
    },
    TravelToMap(MapTravelRequest),
    FindPath {
        actor_id: Option<ActorId>,
        start: GridCoord,
        goal: GridCoord,
    },
    AcknowledgeEvent {
        sequence: u64,
    },
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum ServerMessage {
    Pong,
    Hello {
        protocol_version: u32,
    },
    WorldSnapshot {
        actors: Vec<ActorSnapshot>,
        turn_state: TurnState,
    },
    Snapshot(WorldSnapshotEnvelope),
    Delta(RuntimeEventEnvelope),
    ActionResult(ActionResult),
    InteractionPrompt(InteractionPrompt),
    InteractionExecution(InteractionExecutionResult),
    SceneTransitionRequested(SceneTransitionNotice),
    PathResult {
        path: Vec<GridCoord>,
    },
    Error(ProtocolError),
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ActorSnapshot {
    pub actor_id: ActorId,
    pub kind: ActorKind,
    pub position: WorldCoord,
}

const fn default_true() -> bool {
    true
}
