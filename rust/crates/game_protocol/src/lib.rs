mod messages;
mod narrative;

use bevy_app::prelude::*;

pub use messages::{
    ActorSnapshot, AdvanceOverworldTravelRequest, ClientMessage, DialogueAdvanceRequest,
    EnterLocationRequest, MapTravelRequest, OverworldRouteRequest, ProtocolError,
    ReturnToOverworldRequest, RuntimeEventEnvelope, RuntimeSubscriptionRequest,
    SceneTransitionNotice, ServerMessage, WorldSnapshotEnvelope,
};
pub use narrative::{
    CloudNarrativeDocument, CloudWorkspaceMeta, NarrativeExecutorMode, NarrativeSyncPushDocument,
    NarrativeSyncRequest, NarrativeSyncResponse, NarrativeSyncSettings, PendingSyncOperation,
    ProjectContextSnapshot, SyncConflictPayload,
};

pub struct GameProtocolPlugin;

impl Plugin for GameProtocolPlugin {
    fn build(&self, _app: &mut App) {}
}
