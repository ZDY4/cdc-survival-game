use game_core::{LocationTransitionContext, OverworldRouteSnapshot, OverworldStateSnapshot};
use game_data::{
    ActionRequest, ActionResult, ActorId, ActorKind, DialogueRuntimeState, GridCoord,
    InteractionContextSnapshot, InteractionExecutionRequest, InteractionExecutionResult,
    InteractionPrompt, InteractionTargetId, TurnState, WorldCoord,
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
pub struct OverworldRouteRequest {
    pub actor_id: ActorId,
    #[serde(default)]
    pub target_location_id: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct AdvanceOverworldTravelRequest {
    pub actor_id: ActorId,
    #[serde(default)]
    pub minutes: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct EnterLocationRequest {
    pub actor_id: ActorId,
    #[serde(default)]
    pub location_id: String,
    #[serde(default)]
    pub entry_point_id: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct ReturnToOverworldRequest {
    pub actor_id: ActorId,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct EquipItemRequest {
    pub actor_id: ActorId,
    #[serde(default)]
    pub item_id: u32,
    #[serde(default)]
    pub target_slot: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct UnequipItemRequest {
    pub actor_id: ActorId,
    #[serde(default)]
    pub slot: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct ReloadEquippedWeaponRequest {
    pub actor_id: ActorId,
    #[serde(default)]
    pub slot: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct LearnSkillRequest {
    pub actor_id: ActorId,
    #[serde(default)]
    pub skill_id: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct CraftRecipeRequest {
    pub actor_id: ActorId,
    #[serde(default)]
    pub recipe_id: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct BuyItemRequest {
    pub actor_id: ActorId,
    #[serde(default)]
    pub shop_id: String,
    #[serde(default)]
    pub item_id: u32,
    #[serde(default)]
    pub count: i32,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct SellItemRequest {
    pub actor_id: ActorId,
    #[serde(default)]
    pub shop_id: String,
    #[serde(default)]
    pub item_id: u32,
    #[serde(default)]
    pub count: i32,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct StartQuestRequest {
    pub actor_id: ActorId,
    #[serde(default)]
    pub quest_id: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct ItemEquippedPayload {
    pub actor_id: ActorId,
    #[serde(default)]
    pub item_id: u32,
    #[serde(default)]
    pub slot: Option<String>,
    #[serde(default)]
    pub replaced_item_id: Option<u32>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct ItemUnequippedPayload {
    pub actor_id: ActorId,
    #[serde(default)]
    pub slot: String,
    #[serde(default)]
    pub item_id: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct WeaponReloadedPayload {
    pub actor_id: ActorId,
    #[serde(default)]
    pub slot: String,
    #[serde(default)]
    pub ammo_loaded: i32,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct SkillLearnedPayload {
    pub actor_id: ActorId,
    #[serde(default)]
    pub skill_id: String,
    #[serde(default)]
    pub level: i32,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct RecipeCraftedPayload {
    pub actor_id: ActorId,
    #[serde(default)]
    pub recipe_id: String,
    #[serde(default)]
    pub output_item_id: u32,
    #[serde(default)]
    pub output_count: i32,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct TradeResolvedPayload {
    pub actor_id: ActorId,
    #[serde(default)]
    pub shop_id: String,
    #[serde(default)]
    pub item_id: u32,
    #[serde(default)]
    pub count: i32,
    #[serde(default)]
    pub total_price: i32,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct QuestStartedPayload {
    pub actor_id: ActorId,
    #[serde(default)]
    pub quest_id: String,
    #[serde(default)]
    pub started: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct RuntimeSnapshotSaveRequest {
    #[serde(default)]
    pub snapshot_id: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct RuntimeSnapshotLoadRequest {
    #[serde(default)]
    pub snapshot_id: Option<String>,
    #[serde(default)]
    pub snapshot: Option<Value>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct RuntimeSnapshotPayload {
    #[serde(default)]
    pub snapshot_id: Option<String>,
    #[serde(default = "default_snapshot_schema_version")]
    pub schema_version: u32,
    #[serde(default)]
    pub snapshot: Value,
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
    #[serde(default)]
    pub active_location_id: Option<String>,
    #[serde(default)]
    pub overworld_state: Option<OverworldStateSnapshot>,
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
    pub location_id: Option<String>,
    #[serde(default)]
    pub entry_point_id: Option<String>,
    #[serde(default)]
    pub return_location_id: Option<String>,
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
    RequestOverworldSnapshot,
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
    RequestOverworldRoute(OverworldRouteRequest),
    StartOverworldTravel(OverworldRouteRequest),
    AdvanceOverworldTravel(AdvanceOverworldTravelRequest),
    EnterLocation(EnterLocationRequest),
    ReturnToOverworld(ReturnToOverworldRequest),
    RequestEquipItem(EquipItemRequest),
    RequestUnequipItem(UnequipItemRequest),
    RequestReloadEquippedWeapon(ReloadEquippedWeaponRequest),
    RequestLearnSkill(LearnSkillRequest),
    RequestCraftRecipe(CraftRecipeRequest),
    RequestBuyItem(BuyItemRequest),
    RequestSellItem(SellItemRequest),
    RequestStartQuest(StartQuestRequest),
    RequestRuntimeSnapshotSave(RuntimeSnapshotSaveRequest),
    RequestRuntimeSnapshotLoad(RuntimeSnapshotLoadRequest),
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
    DialogueState(DialogueRuntimeState),
    SceneTransitionRequested(SceneTransitionNotice),
    OverworldRouteComputed(OverworldRouteSnapshot),
    OverworldState(OverworldStateSnapshot),
    LocationTransition(LocationTransitionContext),
    ItemEquipped(ItemEquippedPayload),
    ItemUnequipped(ItemUnequippedPayload),
    WeaponReloaded(WeaponReloadedPayload),
    SkillLearned(SkillLearnedPayload),
    RecipeCrafted(RecipeCraftedPayload),
    ItemBought(TradeResolvedPayload),
    ItemSold(TradeResolvedPayload),
    QuestStarted(QuestStartedPayload),
    RuntimeSnapshotSaved(RuntimeSnapshotPayload),
    RuntimeSnapshotLoaded(RuntimeSnapshotPayload),
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

const fn default_snapshot_schema_version() -> u32 {
    1
}
