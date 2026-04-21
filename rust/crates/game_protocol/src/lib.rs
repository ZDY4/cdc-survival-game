mod messages;

use bevy_app::prelude::*;

pub use messages::{
    ActorSnapshot, BuyItemRequest, ClientMessage, CraftRecipeRequest, DialogueAdvanceRequest,
    EnterLocationRequest, EquipItemRequest, ItemEquippedPayload, ItemUnequippedPayload,
    LearnSkillRequest, MapTravelRequest, ProtocolActorVisionMapSnapshot,
    ProtocolActorVisionSnapshot, ProtocolError, ProtocolLocationTransitionContext,
    ProtocolOverworldStateSnapshot, ProtocolVisionRuntimeSnapshot, QuestStartedPayload,
    RecipeCraftedPayload, ReloadEquippedWeaponRequest, ReturnToOverworldRequest,
    RuntimeEventEnvelope, RuntimeSnapshotLoadRequest, RuntimeSnapshotPayload,
    RuntimeSnapshotSaveRequest, RuntimeSubscriptionRequest, SceneTransitionNotice, SellItemRequest,
    ServerMessage, SkillLearnedPayload, StartQuestRequest, TradeResolvedPayload,
    UnequipItemRequest, WeaponReloadedPayload, WorldSnapshotEnvelope,
};
pub struct GameProtocolPlugin;

impl Plugin for GameProtocolPlugin {
    fn build(&self, _app: &mut App) {}
}
