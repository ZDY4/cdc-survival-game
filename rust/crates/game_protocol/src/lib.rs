mod messages;
mod narrative;

use bevy_app::prelude::*;

pub use messages::{
    ActorSnapshot, AdvanceOverworldTravelRequest, BuyItemRequest, ClientMessage,
    CraftRecipeRequest, DialogueAdvanceRequest, EnterLocationRequest, EquipItemRequest,
    ItemEquippedPayload, ItemUnequippedPayload, LearnSkillRequest, MapTravelRequest,
    OverworldRouteRequest, ProtocolError, QuestStartedPayload, RecipeCraftedPayload,
    ReloadEquippedWeaponRequest, ReturnToOverworldRequest, RuntimeEventEnvelope,
    RuntimeSnapshotLoadRequest, RuntimeSnapshotPayload, RuntimeSnapshotSaveRequest,
    RuntimeSubscriptionRequest, SceneTransitionNotice, SellItemRequest, ServerMessage,
    SkillLearnedPayload, StartQuestRequest, TradeResolvedPayload, UnequipItemRequest,
    WeaponReloadedPayload, WorldSnapshotEnvelope,
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
