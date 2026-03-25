use std::fs;
use std::path::{Path, PathBuf};

use bevy::log::warn;
use game_core::runtime::action_result_status;
use game_core::{NpcActionKey, SimulationEvent};
use game_data::{
    ActorId, CharacterId, DialogueData, DialogueNode, DialogueResolutionContext,
    DialogueResolutionResult, DialogueResolutionSource, DialogueRuleDefinition,
    InteractionExecutionResult, InteractionTargetId,
};

use crate::state::{ActiveDialogueState, ViewerRuntimeState, ViewerState};

const FALLBACK_DIALOGUE_TEXT: &str = "无话可说...";

#[derive(Debug, Clone)]
struct DialogueAssetDirs {
    dialogues_dir: PathBuf,
    dialogue_rules_dir: PathBuf,
}

#[derive(Debug, Clone)]
struct ResolvedDialogueContent {
    result: DialogueResolutionResult,
    data: DialogueData,
}

pub(crate) fn apply_interaction_result(
    runtime_state: &ViewerRuntimeState,
    viewer_state: &mut ViewerState,
    result: InteractionExecutionResult,
) {
    if let Some(prompt) = result.prompt.clone() {
        viewer_state.current_prompt = Some(prompt);
    }

    let dialogue_key = result.dialogue_id.clone();
    if let Some(dialogue_key) = dialogue_key.as_deref() {
        if let Some(actor_id) = viewer_state.selected_actor {
            let target_id = viewer_state
                .current_prompt
                .as_ref()
                .map(|prompt| prompt.target_id.clone())
                .or_else(|| viewer_state.focused_target.clone());
            let target_name = viewer_state
                .current_prompt
                .as_ref()
                .map(|prompt| prompt.target_name.clone())
                .unwrap_or_else(|| dialogue_key.to_string());
            let resolution = open_dialogue(
                runtime_state,
                viewer_state,
                actor_id,
                target_id.as_ref(),
                dialogue_key,
                target_name,
                None,
            );
            viewer_state.status_line = interaction_dialogue_status(&resolution);
            return;
        }
    } else if result.success && result.consumed_target {
        viewer_state.focused_target = None;
        viewer_state.current_prompt = None;
    }

    viewer_state.status_line = if result.approach_required {
        match result.approach_goal {
            Some(goal) => format!(
                "interaction: approaching target via ({}, {}, {})",
                goal.x, goal.y, goal.z
            ),
            None => "interaction: approaching target".to_string(),
        }
    } else if result.success {
        if let Some(context) = result.context_snapshot {
            format!(
                "interaction: ok mode={:?} outdoor={:?} subscene={:?}",
                context.world_mode,
                context.active_outdoor_location_id,
                context.current_subscene_location_id
            )
        } else if let Some(action) = result.action_result {
            format!("interaction: {}", action_result_status(&action))
        } else {
            "interaction: ok".to_string()
        }
    } else {
        format!(
            "interaction: {}",
            result.reason.unwrap_or_else(|| "failed".to_string())
        )
    };
}

pub(crate) fn current_dialogue_node(dialogue: &ActiveDialogueState) -> Option<&DialogueNode> {
    dialogue
        .data
        .nodes
        .iter()
        .find(|node| node.id == dialogue.current_node_id)
}

pub(crate) fn find_dialogue_start_node(dialogue: &DialogueData) -> Option<&DialogueNode> {
    dialogue
        .nodes
        .iter()
        .find(|node| node.is_start)
        .or_else(|| dialogue.nodes.first())
}

pub(crate) fn advance_dialogue(viewer_state: &mut ViewerState, choice_index: Option<usize>) {
    let Some(dialogue) = viewer_state.active_dialogue.as_mut() else {
        return;
    };
    let Some(node) = current_dialogue_node(dialogue).cloned() else {
        viewer_state.active_dialogue = None;
        return;
    };

    let next = match node.node_type.as_str() {
        "choice" => {
            let Some(choice_index) = choice_index else {
                viewer_state.status_line = "dialogue: choose an option with 1-9".to_string();
                return;
            };
            let Some(option) = node.options.get(choice_index) else {
                viewer_state.status_line = "dialogue: invalid choice".to_string();
                return;
            };
            Some(option.next.clone())
        }
        "dialog" | "action" => {
            if node.next.trim().is_empty() {
                None
            } else {
                Some(node.next.clone())
            }
        }
        "end" => None,
        _ => {
            if node.next.trim().is_empty() {
                None
            } else {
                Some(node.next.clone())
            }
        }
    };

    match next {
        Some(next_id) if !next_id.trim().is_empty() => {
            dialogue.current_node_id = next_id;
        }
        _ => {
            viewer_state.active_dialogue = None;
            viewer_state.status_line = "dialogue finished".to_string();
        }
    }
}

pub(crate) fn sync_dialogue_from_event(
    runtime_state: &ViewerRuntimeState,
    viewer_state: &mut ViewerState,
    event: &SimulationEvent,
) {
    match event {
        SimulationEvent::DialogueStarted {
            actor_id,
            target_id,
            dialogue_id,
        } => {
            if !should_follow_dialogue_event(viewer_state, *actor_id) {
                return;
            }

            open_dialogue(
                runtime_state,
                viewer_state,
                *actor_id,
                Some(target_id),
                dialogue_id,
                resolve_target_name(viewer_state, target_id, dialogue_id),
                None,
            );
        }
        SimulationEvent::DialogueAdvanced {
            actor_id,
            dialogue_id,
            node_id,
        } => {
            if !should_follow_dialogue_event(viewer_state, *actor_id) {
                return;
            }

            if viewer_state.active_dialogue.as_ref().map(|dialogue| {
                dialogue.actor_id == *actor_id && dialogue.dialogue_key == *dialogue_id
            }) != Some(true)
            {
                let focused_target = viewer_state.focused_target.clone();
                open_dialogue(
                    runtime_state,
                    viewer_state,
                    *actor_id,
                    focused_target.as_ref(),
                    dialogue_id,
                    resolve_focused_target_name(viewer_state, dialogue_id),
                    Some(node_id.clone()),
                );
                return;
            }

            if let Some(dialogue) = viewer_state.active_dialogue.as_mut() {
                dialogue.current_node_id = node_id.clone();
            }
        }
        _ => {}
    }
}

fn should_follow_dialogue_event(viewer_state: &ViewerState, actor_id: ActorId) -> bool {
    viewer_state.selected_actor == Some(actor_id)
        || viewer_state
            .active_dialogue
            .as_ref()
            .map(|dialogue| dialogue.actor_id)
            == Some(actor_id)
}

fn open_dialogue(
    runtime_state: &ViewerRuntimeState,
    viewer_state: &mut ViewerState,
    actor_id: ActorId,
    target_id: Option<&InteractionTargetId>,
    dialogue_key: &str,
    target_name: String,
    current_node_id: Option<String>,
) -> DialogueResolutionResult {
    let resolved = resolve_dialogue_content(
        runtime_state,
        actor_id,
        target_id,
        dialogue_key,
        target_name.as_str(),
    );
    let current_node_id = current_node_id.unwrap_or_else(|| {
        find_dialogue_start_node(&resolved.data)
            .map(|node| node.id.clone())
            .unwrap_or_else(|| "start".to_string())
    });
    viewer_state.active_dialogue = Some(ActiveDialogueState {
        actor_id,
        dialogue_key: dialogue_key.to_string(),
        dialog_id: resolved
            .result
            .resolved_dialogue_id
            .clone()
            .unwrap_or_else(|| dialogue_key.to_string()),
        data: resolved.data,
        current_node_id,
        target_name,
    });
    resolved.result
}

fn resolve_target_name(
    viewer_state: &ViewerState,
    target_id: &InteractionTargetId,
    dialogue_key: &str,
) -> String {
    if let Some(prompt) = viewer_state.current_prompt.as_ref() {
        if &prompt.target_id == target_id {
            return prompt.target_name.clone();
        }
    }

    match target_id {
        InteractionTargetId::Actor(actor_id) => format!("Actor {:?}", actor_id),
        InteractionTargetId::MapObject(object_id) => {
            if object_id.trim().is_empty() {
                dialogue_key.to_string()
            } else {
                object_id.clone()
            }
        }
    }
}

fn resolve_focused_target_name(viewer_state: &ViewerState, dialogue_key: &str) -> String {
    viewer_state
        .current_prompt
        .as_ref()
        .map(|prompt| prompt.target_name.clone())
        .unwrap_or_else(|| dialogue_key.to_string())
}

fn interaction_dialogue_status(result: &DialogueResolutionResult) -> String {
    if result.used_fallback_dialogue {
        return "interaction: opened fallback dialogue".to_string();
    }
    if let Some(dialogue_id) = result.resolved_dialogue_id.as_deref() {
        return format!("interaction: opened dialogue {}", dialogue_id);
    }
    "interaction: opened dialogue".to_string()
}

fn resolve_dialogue_content(
    runtime_state: &ViewerRuntimeState,
    actor_id: ActorId,
    target_id: Option<&InteractionTargetId>,
    dialogue_key: &str,
    target_name: &str,
) -> ResolvedDialogueContent {
    let context = build_dialogue_resolution_context(runtime_state, actor_id, target_id);
    resolve_dialogue_content_from_context(
        dialogue_key,
        target_name,
        &context,
        &default_dialogue_asset_dirs(),
    )
}

fn resolve_dialogue_content_from_context(
    dialogue_key: &str,
    target_name: &str,
    context: &DialogueResolutionContext,
    asset_dirs: &DialogueAssetDirs,
) -> ResolvedDialogueContent {
    match load_dialogue_rule(dialogue_key, asset_dirs) {
        RuleLoadState::Loaded(rule) => {
            let preview = game_data::resolve_dialogue_preview(&rule, context);
            resolve_from_preview(dialogue_key, target_name, preview, asset_dirs)
        }
        RuleLoadState::Missing => match load_dialogue(dialogue_key, asset_dirs) {
            Ok(dialogue) => ResolvedDialogueContent {
                result: DialogueResolutionResult {
                    dialogue_key: dialogue_key.to_string(),
                    resolved_dialogue_id: Some(dialogue_key.to_string()),
                    source: DialogueResolutionSource::Default,
                    used_fallback_dialogue: false,
                    fallback_reason: None,
                },
                data: dialogue,
            },
            Err(reason) => {
                warn!(
                    "viewer.interaction.dialogue_fallback dialogue_key={} reason={}",
                    dialogue_key, reason
                );
                fallback_dialogue_result(dialogue_key, target_name, reason)
            }
        },
        RuleLoadState::Invalid(reason) => {
            warn!(
                "viewer.interaction.dialogue_fallback dialogue_key={} reason={}",
                dialogue_key, reason
            );
            fallback_dialogue_result(dialogue_key, target_name, reason)
        }
    }
}

fn resolve_from_preview(
    dialogue_key: &str,
    target_name: &str,
    preview: game_data::DialogueResolutionPreview,
    asset_dirs: &DialogueAssetDirs,
) -> ResolvedDialogueContent {
    let Some(resolved_dialogue_id) = preview.resolved_dialogue_id.as_deref() else {
        return fallback_dialogue_result(
            dialogue_key,
            target_name,
            "dialogue_rule_unresolved".to_string(),
        );
    };

    match load_dialogue(resolved_dialogue_id, asset_dirs) {
        Ok(dialogue) => ResolvedDialogueContent {
            result: DialogueResolutionResult {
                dialogue_key: dialogue_key.to_string(),
                resolved_dialogue_id: Some(resolved_dialogue_id.to_string()),
                source: preview.source,
                used_fallback_dialogue: false,
                fallback_reason: None,
            },
            data: dialogue,
        },
        Err(reason) => {
            warn!(
                "viewer.interaction.dialogue_fallback dialogue_key={} resolved_dialogue_id={} reason={}",
                dialogue_key, resolved_dialogue_id, reason
            );
            fallback_dialogue_result(dialogue_key, target_name, reason)
        }
    }
}

fn fallback_dialogue_result(
    dialogue_key: &str,
    target_name: &str,
    reason: String,
) -> ResolvedDialogueContent {
    ResolvedDialogueContent {
        result: DialogueResolutionResult {
            dialogue_key: dialogue_key.to_string(),
            resolved_dialogue_id: None,
            source: DialogueResolutionSource::Unresolved,
            used_fallback_dialogue: true,
            fallback_reason: Some(reason),
        },
        data: fallback_dialogue(dialogue_key, target_name),
    }
}

fn build_dialogue_resolution_context(
    runtime_state: &ViewerRuntimeState,
    actor_id: ActorId,
    target_id: Option<&InteractionTargetId>,
) -> DialogueResolutionContext {
    let snapshot = runtime_state.runtime.snapshot();
    let actor_state = snapshot
        .actors
        .iter()
        .find(|actor| actor.actor_id == actor_id);

    let player_hp_ratio = actor_state
        .map(|actor| {
            if actor.max_hp <= 0.0 {
                1.0
            } else {
                (actor.hp / actor.max_hp).clamp(0.0, 1.0)
            }
        })
        .unwrap_or(1.0);

    let target_actor_definition_id = target_id.and_then(|target_id| match target_id {
        InteractionTargetId::Actor(target_actor_id) => snapshot
            .actors
            .iter()
            .find(|actor| actor.actor_id == *target_actor_id)
            .and_then(|actor| actor.definition_id.as_ref())
            .map(CharacterId::as_str)
            .map(str::to_string),
        InteractionTargetId::MapObject(_) => None,
    });
    let npc_debug_entry = target_actor_definition_id
        .as_deref()
        .and_then(|definition_id| {
            runtime_state
                .ai_snapshot
                .entries
                .iter()
                .find(|entry| entry.definition_id == definition_id)
        });

    DialogueResolutionContext {
        world_mode: snapshot.interaction_context.world_mode,
        map_id: snapshot.interaction_context.current_map_id.clone(),
        outdoor_location_id: snapshot
            .interaction_context
            .active_outdoor_location_id
            .clone(),
        subscene_location_id: snapshot
            .interaction_context
            .current_subscene_location_id
            .clone(),
        player_level: actor_state.map(|actor| actor.level).unwrap_or(1),
        player_hp_ratio,
        player_active_quests: runtime_state.runtime.active_quest_ids_for_actor(actor_id),
        player_completed_quests: runtime_state.runtime.completed_quest_ids(),
        relation_score: target_id.and_then(|target_id| match target_id {
            InteractionTargetId::Actor(target_actor_id) => Some(
                runtime_state
                    .runtime
                    .get_relationship_score(actor_id, *target_actor_id),
            ),
            InteractionTargetId::MapObject(_) => None,
        }),
        npc_definition_id: target_actor_definition_id,
        npc_role: npc_debug_entry.map(|entry| entry.role),
        npc_on_shift: npc_debug_entry.map(|entry| entry.on_shift),
        npc_schedule_labels: npc_debug_entry
            .and_then(|entry| {
                if entry.schedule_label.trim().is_empty() {
                    None
                } else {
                    Some(vec![entry.schedule_label.clone()])
                }
            })
            .unwrap_or_default(),
        npc_action: npc_debug_entry.and_then(|entry| entry.action.map(npc_action_key_name)),
        npc_morale: npc_debug_entry.map(|entry| f32::from(entry.need_morale)),
    }
}

fn fallback_dialogue(dialogue_key: &str, target_name: &str) -> DialogueData {
    DialogueData {
        dialog_id: dialogue_key.to_string(),
        nodes: vec![DialogueNode {
            id: "start".to_string(),
            node_type: "dialog".to_string(),
            speaker: target_name.to_string(),
            text: FALLBACK_DIALOGUE_TEXT.to_string(),
            is_start: true,
            ..DialogueNode::default()
        }],
        ..DialogueData::default()
    }
}

fn default_dialogue_asset_dirs() -> DialogueAssetDirs {
    let data_root = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../../data");
    DialogueAssetDirs {
        dialogues_dir: data_root.join("dialogues"),
        dialogue_rules_dir: data_root.join("dialogue_rules"),
    }
}

fn npc_action_key_name(action: NpcActionKey) -> String {
    match action {
        NpcActionKey::TravelToDutyArea => "travel_to_duty_area",
        NpcActionKey::ReserveGuardPost => "reserve_guard_post",
        NpcActionKey::StandGuard => "stand_guard",
        NpcActionKey::PatrolRoute => "patrol_route",
        NpcActionKey::TravelToCanteen => "travel_to_canteen",
        NpcActionKey::EatMeal => "eat_meal",
        NpcActionKey::RestockMealService => "restock_meal_service",
        NpcActionKey::TreatPatients => "treat_patients",
        NpcActionKey::TravelToLeisure => "travel_to_leisure",
        NpcActionKey::Relax => "relax",
        NpcActionKey::TravelHome => "travel_home",
        NpcActionKey::ReserveBed => "reserve_bed",
        NpcActionKey::Sleep => "sleep",
        NpcActionKey::RaiseAlarm => "raise_alarm",
        NpcActionKey::RespondAlarm => "respond_alarm",
        NpcActionKey::IdleSafely => "idle_safely",
    }
    .to_string()
}

enum RuleLoadState {
    Loaded(DialogueRuleDefinition),
    Missing,
    Invalid(String),
}

fn load_dialogue_rule(dialogue_key: &str, asset_dirs: &DialogueAssetDirs) -> RuleLoadState {
    let path = asset_dirs
        .dialogue_rules_dir
        .join(format!("{dialogue_key}.json"));
    let raw = match fs::read_to_string(&path) {
        Ok(raw) => raw,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
            return RuleLoadState::Missing
        }
        Err(error) => {
            return RuleLoadState::Invalid(format!("dialogue_rule_read_failed:{}", error));
        }
    };

    match serde_json::from_str::<DialogueRuleDefinition>(&raw) {
        Ok(mut definition) => {
            if definition.dialogue_key.trim().is_empty() {
                definition.dialogue_key = dialogue_key.to_string();
            }
            RuleLoadState::Loaded(definition)
        }
        Err(error) => RuleLoadState::Invalid(format!("dialogue_rule_parse_failed:{error}")),
    }
}

fn load_dialogue(
    dialogue_id: &str,
    asset_dirs: &DialogueAssetDirs,
) -> Result<DialogueData, String> {
    let path = asset_dirs.dialogues_dir.join(format!("{dialogue_id}.json"));
    let raw = fs::read_to_string(&path).map_err(|error| {
        if error.kind() == std::io::ErrorKind::NotFound {
            format!("dialogue_missing:{dialogue_id}")
        } else {
            format!("dialogue_read_failed:{error}")
        }
    })?;
    let mut dialogue = serde_json::from_str::<DialogueData>(&raw)
        .map_err(|error| format!("dialogue_parse_failed:{error}"))?;
    if dialogue.dialog_id.trim().is_empty() {
        dialogue.dialog_id = file_stem_id(&path);
    }
    Ok(dialogue)
}

fn file_stem_id(path: &Path) -> String {
    path.file_stem()
        .and_then(|value| value.to_str())
        .unwrap_or_default()
        .to_string()
}

#[cfg(test)]
mod tests {
    use std::fs;
    use std::path::{Path, PathBuf};
    use std::time::{SystemTime, UNIX_EPOCH};

    use serde_json::json;

    use super::{advance_dialogue, resolve_dialogue_content_from_context, DialogueAssetDirs};
    use crate::state::{ActiveDialogueState, ViewerState};
    use game_data::{
        ActorId, DialogueData, DialogueNode, DialogueOption, DialogueResolutionContext,
        DialogueResolutionSource, NpcRole, WorldMode,
    };

    #[test]
    fn choice_dialogue_requires_explicit_selection() {
        let mut viewer_state = ViewerState::default();
        viewer_state.active_dialogue = Some(ActiveDialogueState {
            actor_id: ActorId(1),
            dialogue_key: "test".to_string(),
            dialog_id: "test".to_string(),
            data: DialogueData {
                dialog_id: "test".to_string(),
                nodes: vec![DialogueNode {
                    id: "start".to_string(),
                    node_type: "choice".to_string(),
                    text: "Choose".to_string(),
                    options: vec![DialogueOption {
                        text: "Option".to_string(),
                        next: "end".to_string(),
                        ..DialogueOption::default()
                    }],
                    is_start: true,
                    ..DialogueNode::default()
                }],
                ..DialogueData::default()
            },
            current_node_id: "start".to_string(),
            target_name: "NPC".to_string(),
        });

        advance_dialogue(&mut viewer_state, None);

        assert!(viewer_state.active_dialogue.is_some());
        assert_eq!(
            viewer_state.status_line,
            "dialogue: choose an option with 1-9"
        );
    }

    #[test]
    fn dialogue_rules_select_variant_and_actual_resolution_matches_preview() {
        let temp_dir = create_temp_dir("dialogue_rules_select_variant");
        write_json(
            &temp_dir.join("dialogue_rules").join("doctor_chen.json"),
            &json!({
                "dialogue_key": "doctor_chen",
                "default_dialogue_id": "doctor_chen_default",
                "variants": [{
                    "dialogue_id": "doctor_chen_medical",
                    "when": {
                        "npc_role_in": ["doctor"],
                        "npc_on_shift": true,
                        "player_hp_ratio_max": 0.5
                    }
                }]
            }),
        );
        write_json(
            &temp_dir.join("dialogues").join("doctor_chen_default.json"),
            &json!({
                "dialog_id": "doctor_chen_default",
                "nodes": [{
                    "id": "start",
                    "type": "dialog",
                    "speaker": "陈医生",
                    "text": "默认对话",
                    "is_start": true
                }]
            }),
        );
        write_json(
            &temp_dir.join("dialogues").join("doctor_chen_medical.json"),
            &json!({
                "dialog_id": "doctor_chen_medical",
                "nodes": [{
                    "id": "start",
                    "type": "dialog",
                    "speaker": "陈医生",
                    "text": "你看起来伤得不轻。",
                    "is_start": true
                }]
            }),
        );

        let resolved = resolve_dialogue_content_from_context(
            "doctor_chen",
            "陈医生",
            &DialogueResolutionContext {
                world_mode: WorldMode::Interior,
                player_level: 5,
                player_hp_ratio: 0.35,
                npc_role: Some(NpcRole::Doctor),
                npc_on_shift: Some(true),
                ..DialogueResolutionContext::default()
            },
            &test_dialogue_asset_dirs(&temp_dir),
        );

        assert_eq!(
            resolved.result.resolved_dialogue_id.as_deref(),
            Some("doctor_chen_medical")
        );
        assert_eq!(resolved.result.source, DialogueResolutionSource::Variant);
        assert_eq!(resolved.data.dialog_id, "doctor_chen_medical");
    }

    #[test]
    fn missing_dialogue_file_falls_back_to_builtin_line() {
        let temp_dir = create_temp_dir("missing_dialogue_file_falls_back");
        write_json(
            &temp_dir.join("dialogue_rules").join("trader_lao_wang.json"),
            &json!({
                "dialogue_key": "trader_lao_wang",
                "default_dialogue_id": "missing_dialogue"
            }),
        );

        let resolved = resolve_dialogue_content_from_context(
            "trader_lao_wang",
            "老王",
            &DialogueResolutionContext::default(),
            &test_dialogue_asset_dirs(&temp_dir),
        );

        assert!(resolved.result.used_fallback_dialogue);
        assert_eq!(resolved.result.resolved_dialogue_id, None);
        assert_eq!(
            resolved.data.nodes.first().map(|node| node.text.as_str()),
            Some("无话可说...")
        );
        assert_eq!(
            resolved
                .data
                .nodes
                .first()
                .map(|node| node.speaker.as_str()),
            Some("老王")
        );
    }

    fn test_dialogue_asset_dirs(root: &Path) -> DialogueAssetDirs {
        DialogueAssetDirs {
            dialogues_dir: root.join("dialogues"),
            dialogue_rules_dir: root.join("dialogue_rules"),
        }
    }

    fn create_temp_dir(label: &str) -> PathBuf {
        let unique = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("system time should be after epoch")
            .as_nanos();
        let dir = std::env::temp_dir().join(format!("viewer_dialogue_{label}_{unique}"));
        fs::create_dir_all(dir.join("dialogues")).expect("dialogues dir should exist");
        fs::create_dir_all(dir.join("dialogue_rules")).expect("rules dir should exist");
        dir
    }

    fn write_json(path: &Path, value: &serde_json::Value) {
        let raw = serde_json::to_string_pretty(value).expect("json should serialize");
        fs::write(path, raw).expect("json file should be written");
    }
}
