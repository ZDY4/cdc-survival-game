use game_data::{
    ActionRequest, ActionResult, ActorId, ActorKind, DialogueRuntimeState, GridCoord,
    InteractionContextSnapshot, InteractionExecutionRequest, InteractionExecutionResult,
    InteractionPrompt, InteractionTargetId, MapId, TurnState, WorldCoord, WorldMode,
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

#[derive(Debug, Clone, Serialize, Deserialize, Default, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ProtocolLocationTransitionContext {
    #[serde(default)]
    pub location_id: String,
    #[serde(default)]
    pub map_id: String,
    #[serde(default)]
    pub entry_point_id: String,
    #[serde(default)]
    pub return_outdoor_location_id: Option<String>,
    #[serde(default)]
    pub return_entry_point_id: Option<String>,
    #[serde(default)]
    pub world_mode: WorldMode,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ProtocolOverworldStateSnapshot {
    #[serde(default)]
    pub overworld_id: Option<String>,
    #[serde(default)]
    pub active_location_id: Option<String>,
    #[serde(default)]
    pub active_outdoor_location_id: Option<String>,
    #[serde(default)]
    pub current_map_id: Option<String>,
    #[serde(default)]
    pub current_entry_point_id: Option<String>,
    #[serde(default)]
    pub current_overworld_cell: Option<GridCoord>,
    #[serde(default)]
    pub unlocked_locations: Vec<String>,
    #[serde(default)]
    pub world_mode: WorldMode,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct ProtocolActorVisionMapSnapshot {
    pub map_id: MapId,
    #[serde(default)]
    pub explored_cells: Vec<GridCoord>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct ProtocolActorVisionSnapshot {
    pub actor_id: ActorId,
    #[serde(default)]
    pub radius: i32,
    #[serde(default)]
    pub active_map_id: Option<MapId>,
    #[serde(default)]
    pub visible_cells: Vec<GridCoord>,
    #[serde(default)]
    pub explored_maps: Vec<ProtocolActorVisionMapSnapshot>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct ProtocolVisionRuntimeSnapshot {
    #[serde(default)]
    pub actors: Vec<ProtocolActorVisionSnapshot>,
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
    pub overworld_state: Option<ProtocolOverworldStateSnapshot>,
    #[serde(default)]
    pub vision_state: Option<ProtocolVisionRuntimeSnapshot>,
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
    OverworldState(ProtocolOverworldStateSnapshot),
    LocationTransition(ProtocolLocationTransitionContext),
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

#[cfg(test)]
mod tests {
    use super::{
        ActorSnapshot, ProtocolActorVisionMapSnapshot, ProtocolActorVisionSnapshot,
        ProtocolOverworldStateSnapshot, ProtocolVisionRuntimeSnapshot, WorldSnapshotEnvelope,
    };
    use game_data::{ActorId, ActorKind, GridCoord, InteractionContextSnapshot, MapId, TurnState};

    #[test]
    fn world_snapshot_envelope_round_trips_with_protocol_owned_dtos() {
        let envelope = WorldSnapshotEnvelope {
            sequence: 42,
            actors: vec![ActorSnapshot {
                actor_id: ActorId(7),
                kind: ActorKind::Player,
                position: game_data::WorldCoord::new(1.0, 0.0, 2.0),
            }],
            turn_state: TurnState {
                combat_active: true,
                current_actor_id: Some(ActorId(7)),
                current_group_id: Some("player".into()),
                current_turn_index: 3,
            },
            interaction_context: Some(InteractionContextSnapshot::default()),
            active_map_id: Some("test_map".into()),
            active_location_id: Some("safe_house".into()),
            overworld_state: Some(ProtocolOverworldStateSnapshot {
                current_map_id: Some("test_map".into()),
                active_location_id: Some("safe_house".into()),
                unlocked_locations: vec!["safe_house".into()],
                ..Default::default()
            }),
            vision_state: Some(ProtocolVisionRuntimeSnapshot {
                actors: vec![ProtocolActorVisionSnapshot {
                    actor_id: ActorId(7),
                    radius: 8,
                    active_map_id: Some(MapId("test_map".into())),
                    visible_cells: vec![GridCoord::new(1, 0, 2)],
                    explored_maps: vec![ProtocolActorVisionMapSnapshot {
                        map_id: MapId("test_map".into()),
                        explored_cells: vec![GridCoord::new(1, 0, 2)],
                    }],
                }],
            }),
        };

        let value = serde_json::to_value(&envelope).expect("snapshot should serialize");
        let decoded: WorldSnapshotEnvelope =
            serde_json::from_value(value).expect("snapshot should deserialize");

        assert_eq!(decoded.sequence, 42);
        assert_eq!(
            decoded
                .overworld_state
                .as_ref()
                .and_then(|state| state.current_map_id.as_deref()),
            Some("test_map")
        );
        assert_eq!(
            decoded
                .vision_state
                .as_ref()
                .and_then(|state| state.actors.first())
                .and_then(|actor| actor.active_map_id.as_ref())
                .map(MapId::as_str),
            Some("test_map")
        );
    }
}
