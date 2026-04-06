use std::fs;
use std::path::{Path, PathBuf};

use bevy::log::warn;
use game_core::runtime::action_result_status;
use game_core::{NpcActionKey, SimulationEvent};
use game_data::{
    advance_dialogue as advance_dialogue_local_runtime,
    current_dialogue_node as current_dialogue_node_runtime, resolve_dialogue_start_node_id,
    ActorId, CharacterId, DialogueAdvanceError, DialogueData, DialogueNode,
    DialogueResolutionContext, DialogueResolutionResult, DialogueResolutionSource,
    DialogueRuleDefinition, DialogueRuntimeState, InteractionExecutionResult, InteractionTargetId,
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

    if let Some(dialogue_state) = result.dialogue_state.clone() {
        let dialogue_key = if dialogue_state.session.dialogue_key.trim().is_empty() {
            dialogue_state.session.dialogue_id.clone()
        } else {
            dialogue_state.session.dialogue_key.clone()
        };
        let target_name = viewer_state
            .current_prompt
            .as_ref()
            .map(|prompt| prompt.target_name.clone())
            .unwrap_or_else(|| dialogue_key.clone());
        apply_dialogue_runtime_state(viewer_state, dialogue_state, target_name);
        return;
    }

    let dialogue_key = result.dialogue_id.clone();
    if let Some(dialogue_key) = dialogue_key.as_deref() {
        let snapshot = runtime_state.runtime.snapshot();
        if let Some(actor_id) = viewer_state.command_actor_id(&snapshot) {
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
    current_dialogue_node_runtime(&dialogue.data, &dialogue.current_node_id)
}

pub(crate) fn current_dialogue_has_options(dialogue: &ActiveDialogueState) -> bool {
    current_dialogue_node(dialogue)
        .map(|node| !node.options.is_empty())
        .unwrap_or(false)
}

pub(crate) fn advance_dialogue(
    runtime_state: &mut ViewerRuntimeState,
    viewer_state: &mut ViewerState,
    choice_index: Option<usize>,
) {
    let Some(dialogue) = viewer_state.active_dialogue.clone() else {
        return;
    };

    if runtime_state
        .runtime
        .active_dialogue_state(dialogue.actor_id)
        .is_none()
    {
        advance_dialogue_with_local_state(viewer_state, dialogue, choice_index);
        return;
    }

    match runtime_state.runtime.advance_dialogue(
        dialogue.actor_id,
        dialogue.target_id.clone(),
        &dialogue.dialogue_key,
        None,
        choice_index,
    ) {
        Ok(dialogue_state) => {
            apply_dialogue_runtime_state(viewer_state, dialogue_state, dialogue.target_name);
        }
        Err(reason) if reason.starts_with("dialogue_choice_required:") => {
            viewer_state.status_line = "dialogue: click an option or press 1-9".to_string();
        }
        Err(reason)
            if reason.starts_with("dialogue_invalid_choice:")
                || reason.starts_with("dialogue_choice_invalid:")
                || reason.starts_with("dialogue_option_unresolved:") =>
        {
            viewer_state.status_line = "dialogue: invalid choice".to_string();
        }
        Err(reason)
            if reason.starts_with("dialogue_missing_node:")
                || reason.starts_with("dialogue_node_missing:") =>
        {
            viewer_state.active_dialogue = None;
            viewer_state.status_line = "dialogue: current node missing".to_string();
        }
        Err(reason)
            if reason.starts_with("dialogue_session_missing")
                || reason.starts_with("dialogue_definition_missing:") =>
        {
            advance_dialogue_with_local_state(viewer_state, dialogue, choice_index);
        }
        Err(reason) => {
            viewer_state.status_line = format!("dialogue: {reason}");
        }
    }
}

fn advance_dialogue_with_local_state(
    viewer_state: &mut ViewerState,
    dialogue: ActiveDialogueState,
    choice_index: Option<usize>,
) {
    match advance_dialogue_local_runtime(&dialogue.data, &dialogue.current_node_id, choice_index) {
        Ok(outcome) => {
            if let Some(next_node_id) = outcome.next_node_id {
                if let Some(active_dialogue) = viewer_state.active_dialogue.as_mut() {
                    active_dialogue.current_node_id = next_node_id.clone();
                }
                viewer_state.status_line = format!("dialogue node: {next_node_id}");
                return;
            }

            viewer_state.active_dialogue = None;
            viewer_state.status_line = match outcome.end_type {
                Some(end_type) => format!("dialogue finished: {end_type}"),
                None => "dialogue finished".to_string(),
            };
        }
        Err(DialogueAdvanceError::ChoiceRequired { .. }) => {
            viewer_state.status_line = "dialogue: click an option or press 1-9".to_string();
        }
        Err(DialogueAdvanceError::InvalidChoice { .. }) => {
            viewer_state.status_line = "dialogue: invalid choice".to_string();
        }
        Err(DialogueAdvanceError::MissingNode { .. }) => {
            viewer_state.active_dialogue = None;
            viewer_state.status_line = "dialogue: current node missing".to_string();
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
            if !should_follow_dialogue_event(runtime_state, viewer_state, *actor_id) {
                return;
            }

            if let Some(dialogue_state) = runtime_state.runtime.active_dialogue_state(*actor_id) {
                apply_dialogue_runtime_state(
                    viewer_state,
                    dialogue_state,
                    resolve_target_name(viewer_state, target_id, dialogue_id),
                );
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
            if !should_follow_dialogue_event(runtime_state, viewer_state, *actor_id) {
                return;
            }

            if let Some(dialogue_state) = runtime_state.runtime.active_dialogue_state(*actor_id) {
                let target_name = viewer_state
                    .active_dialogue
                    .as_ref()
                    .map(|dialogue| dialogue.target_name.clone())
                    .unwrap_or_else(|| resolve_focused_target_name(viewer_state, dialogue_id));
                apply_dialogue_runtime_state(viewer_state, dialogue_state, target_name);
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

fn should_follow_dialogue_event(
    runtime_state: &ViewerRuntimeState,
    viewer_state: &ViewerState,
    actor_id: ActorId,
) -> bool {
    let snapshot = runtime_state.runtime.snapshot();
    viewer_state
        .active_dialogue
        .as_ref()
        .map(|dialogue| dialogue.actor_id)
        == Some(actor_id)
        || viewer_state.command_actor_id(&snapshot) == Some(actor_id)
        || viewer_state.focus_actor_id(&snapshot) == Some(actor_id)
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
        resolve_dialogue_start_node_id(&resolved.data).unwrap_or_else(|| "start".to_string())
    });
    viewer_state.active_dialogue = Some(ActiveDialogueState {
        actor_id,
        target_id: target_id.cloned(),
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

fn apply_dialogue_runtime_state(
    viewer_state: &mut ViewerState,
    dialogue_state: DialogueRuntimeState,
    target_name: String,
) {
    viewer_state.pending_open_trade_target = dialogue_state
        .emitted_actions
        .iter()
        .any(|action| action.action_type == "open_trade")
        .then(|| dialogue_state.session.target_id.clone())
        .flatten();

    if dialogue_state.finished {
        viewer_state.active_dialogue = None;
        viewer_state.status_line = dialogue_runtime_status(&dialogue_state);
        return;
    }

    let dialogue_key = if dialogue_state.session.dialogue_key.trim().is_empty() {
        dialogue_state.session.dialogue_id.clone()
    } else {
        dialogue_state.session.dialogue_key.clone()
    };
    let dialog_id = if dialogue_state.session.dialogue_id.trim().is_empty() {
        dialogue_key.clone()
    } else {
        dialogue_state.session.dialogue_id.clone()
    };

    viewer_state.active_dialogue = Some(ActiveDialogueState {
        actor_id: dialogue_state.session.actor_id,
        target_id: dialogue_state.session.target_id.clone(),
        dialogue_key,
        dialog_id: dialog_id.clone(),
        data: dialogue_data_from_runtime_state(&dialogue_state, &dialog_id),
        current_node_id: dialogue_state.session.current_node_id.clone(),
        target_name,
    });
    viewer_state.status_line = dialogue_runtime_status(&dialogue_state);
}

fn dialogue_data_from_runtime_state(
    dialogue_state: &DialogueRuntimeState,
    dialog_id: &str,
) -> DialogueData {
    let current_node = dialogue_state
        .current_node
        .clone()
        .unwrap_or_else(|| DialogueNode {
            id: dialogue_state.session.current_node_id.clone(),
            node_type: "dialog".to_string(),
            ..DialogueNode::default()
        });

    DialogueData {
        dialog_id: dialog_id.to_string(),
        nodes: vec![DialogueNode {
            options: if dialogue_state.available_options.is_empty() {
                current_node.options.clone()
            } else {
                dialogue_state.available_options.clone()
            },
            ..current_node
        }],
        ..DialogueData::default()
    }
}

fn dialogue_runtime_status(dialogue_state: &DialogueRuntimeState) -> String {
    if dialogue_state.finished {
        if let Some(end_type) = dialogue_state.end_type.as_deref() {
            return format!("dialogue finished: {}", end_type);
        }
        return "dialogue finished".to_string();
    }

    if !dialogue_state.emitted_actions.is_empty() {
        let actions = dialogue_state
            .emitted_actions
            .iter()
            .map(|action| action.action_type.as_str())
            .collect::<Vec<_>>()
            .join(", ");
        return format!("dialogue actions: {}", actions);
    }

    format!("dialogue node: {}", dialogue_state.session.current_node_id)
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
        npc_action: npc_debug_entry.and_then(|entry| entry.action.clone().map(npc_action_key_name)),
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
    action.as_str().to_string()
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

    use game_bevy::SettlementDebugSnapshot;
    use game_core::{RegisterActor, Simulation, SimulationRuntime};
    use serde_json::json;

    use super::{
        advance_dialogue, apply_interaction_result, current_dialogue_has_options,
        resolve_dialogue_content_from_context, sync_dialogue_from_event, DialogueAssetDirs,
    };
    use crate::state::{ActiveDialogueState, ViewerRuntimeState, ViewerState};
    use game_data::{
        ActorKind, ActorSide, CharacterId, DialogueData, DialogueLibrary, DialogueNode,
        DialogueOption, DialogueResolutionContext, DialogueResolutionSource, InteractionOptionId,
        InteractionTargetId, NpcRole, WorldMode,
    };

    #[test]
    fn choice_dialogue_requires_explicit_selection() {
        let mut simulation = Simulation::new();
        simulation.set_dialogue_library(DialogueLibrary::from(std::collections::BTreeMap::from([
            (
                "test".to_string(),
                DialogueData {
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
            ),
        ])));
        let player = simulation.register_actor(RegisterActor {
            definition_id: Some(CharacterId("player".into())),
            display_name: "Player".into(),
            kind: ActorKind::Player,
            side: ActorSide::Player,
            group_id: "player".into(),
            grid_position: game_data::GridCoord::new(0, 0, 0),
            interaction: None,
            attack_range: 1.2,
            ai_controller: None,
        });
        let npc = simulation.register_actor(RegisterActor {
            definition_id: Some(CharacterId("test".into())),
            display_name: "NPC".into(),
            kind: ActorKind::Npc,
            side: ActorSide::Friendly,
            group_id: "friendly".into(),
            grid_position: game_data::GridCoord::new(1, 0, 0),
            interaction: None,
            attack_range: 1.2,
            ai_controller: None,
        });
        let mut runtime_state = ViewerRuntimeState {
            runtime: SimulationRuntime::from_simulation(simulation),
            recent_events: Vec::new(),
            ai_snapshot: SettlementDebugSnapshot::default(),
        };
        let mut viewer_state = ViewerState::default();
        viewer_state.selected_actor = Some(player);
        viewer_state.focused_target = Some(InteractionTargetId::Actor(npc));

        let result = runtime_state.runtime.issue_interaction(
            player,
            InteractionTargetId::Actor(npc),
            InteractionOptionId("talk".into()),
        );
        apply_interaction_result(&runtime_state, &mut viewer_state, result);
        advance_dialogue(&mut runtime_state, &mut viewer_state, None);

        assert!(viewer_state.active_dialogue.is_some());
        assert_eq!(
            viewer_state.status_line,
            "dialogue: click an option or press 1-9"
        );
    }

    #[test]
    fn dialogue_started_event_follows_controlled_player_after_approach() {
        let mut simulation = Simulation::new();
        simulation.set_dialogue_library(DialogueLibrary::from(std::collections::BTreeMap::from([
            (
                "test".to_string(),
                DialogueData {
                    dialog_id: "test".to_string(),
                    nodes: vec![DialogueNode {
                        id: "start".to_string(),
                        node_type: "dialog".to_string(),
                        text: "Hello".to_string(),
                        is_start: true,
                        ..DialogueNode::default()
                    }],
                    ..DialogueData::default()
                },
            ),
        ])));
        let player = simulation.register_actor(RegisterActor {
            definition_id: Some(CharacterId("player".into())),
            display_name: "Player".into(),
            kind: ActorKind::Player,
            side: ActorSide::Player,
            group_id: "player".into(),
            grid_position: game_data::GridCoord::new(0, 0, 1),
            interaction: None,
            attack_range: 1.2,
            ai_controller: None,
        });
        let npc = simulation.register_actor(RegisterActor {
            definition_id: Some(CharacterId("test".into())),
            display_name: "NPC".into(),
            kind: ActorKind::Npc,
            side: ActorSide::Friendly,
            group_id: "friendly".into(),
            grid_position: game_data::GridCoord::new(2, 0, 1),
            interaction: None,
            attack_range: 1.2,
            ai_controller: None,
        });
        simulation.set_actor_ap(player, 1.0);

        let mut runtime_state = ViewerRuntimeState {
            runtime: SimulationRuntime::from_simulation(simulation),
            recent_events: Vec::new(),
            ai_snapshot: SettlementDebugSnapshot::default(),
        };
        let mut viewer_state = ViewerState::default();
        viewer_state.select_actor(player, ActorSide::Player);
        viewer_state.focused_target = Some(InteractionTargetId::Actor(npc));

        let result = runtime_state.runtime.issue_interaction(
            player,
            InteractionTargetId::Actor(npc),
            InteractionOptionId("talk".into()),
        );
        apply_interaction_result(&runtime_state, &mut viewer_state, result.clone());

        assert!(result.approach_required);
        assert_eq!(viewer_state.selected_actor, None);
        assert_eq!(viewer_state.controlled_player_actor, Some(player));
        assert!(viewer_state.active_dialogue.is_none());

        for event in runtime_state.runtime.drain_events() {
            sync_dialogue_from_event(&runtime_state, &mut viewer_state, &event);
        }
        assert!(viewer_state.active_dialogue.is_none());

        let world_cycle = runtime_state.runtime.advance_pending_progression();
        assert_eq!(
            world_cycle.applied_step,
            Some(game_core::PendingProgressionStep::RunNonCombatWorldCycle)
        );
        for event in runtime_state.runtime.drain_events() {
            sync_dialogue_from_event(&runtime_state, &mut viewer_state, &event);
        }
        assert!(viewer_state.active_dialogue.is_none());

        let next_turn = runtime_state.runtime.advance_pending_progression();
        assert_eq!(
            next_turn.applied_step,
            Some(game_core::PendingProgressionStep::StartNextNonCombatPlayerTurn)
        );
        for event in runtime_state.runtime.drain_events() {
            sync_dialogue_from_event(&runtime_state, &mut viewer_state, &event);
        }

        let active_dialogue = viewer_state
            .active_dialogue
            .as_ref()
            .expect("dialogue should open after pending interaction resumes");
        assert_eq!(active_dialogue.actor_id, player);
        assert_eq!(active_dialogue.target_id, Some(InteractionTargetId::Actor(npc)));
        assert_eq!(active_dialogue.current_node_id, "start");
    }

    #[test]
    fn current_dialogue_has_options_detects_choice_nodes() {
        let dialogue = ActiveDialogueState {
            actor_id: game_data::ActorId(1),
            target_id: Some(InteractionTargetId::MapObject("npc".into())),
            dialogue_key: "viewer_only".into(),
            dialog_id: "viewer_only".into(),
            data: DialogueData {
                dialog_id: "viewer_only".into(),
                nodes: vec![DialogueNode {
                    id: "start".into(),
                    node_type: "choice".into(),
                    text: "临时对话".into(),
                    options: vec![DialogueOption {
                        text: "继续".into(),
                        next: "end".into(),
                        ..DialogueOption::default()
                    }],
                    is_start: true,
                    ..DialogueNode::default()
                }],
                ..DialogueData::default()
            },
            current_node_id: "start".into(),
            target_name: "NPC".into(),
        };

        assert!(current_dialogue_has_options(&dialogue));
    }

    #[test]
    fn local_viewer_dialogue_can_finish_without_runtime_session() {
        let (runtime, _) = game_core::create_demo_runtime();
        let mut runtime_state = ViewerRuntimeState {
            runtime,
            recent_events: Vec::new(),
            ai_snapshot: SettlementDebugSnapshot::default(),
        };
        let mut viewer_state = ViewerState::default();
        viewer_state.active_dialogue = Some(ActiveDialogueState {
            actor_id: game_data::ActorId(99),
            target_id: Some(InteractionTargetId::MapObject("npc".into())),
            dialogue_key: "viewer_only".into(),
            dialog_id: "viewer_only".into(),
            data: DialogueData {
                dialog_id: "viewer_only".into(),
                nodes: vec![DialogueNode {
                    id: "start".into(),
                    node_type: "dialog".into(),
                    text: "临时对话".into(),
                    is_start: true,
                    ..DialogueNode::default()
                }],
                ..DialogueData::default()
            },
            current_node_id: "start".into(),
            target_name: "NPC".into(),
        });

        advance_dialogue(&mut runtime_state, &mut viewer_state, None);

        assert!(viewer_state.active_dialogue.is_none());
        assert_eq!(viewer_state.status_line, "dialogue finished");
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
