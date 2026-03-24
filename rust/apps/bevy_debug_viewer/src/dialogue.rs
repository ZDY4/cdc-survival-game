use std::fs;
use std::path::PathBuf;

use game_core::runtime::action_result_status;
use game_data::{DialogueData, DialogueNode, InteractionExecutionResult};

use crate::state::{ActiveDialogueState, ViewerState};

pub(crate) fn apply_interaction_result(
    viewer_state: &mut ViewerState,
    result: InteractionExecutionResult,
) {
    if let Some(prompt) = result.prompt.clone() {
        viewer_state.current_prompt = Some(prompt);
    }

    if let Some(dialog_id) = result.dialogue_id.as_ref() {
        if let Some(dialogue) = load_dialogue(dialog_id) {
            let current_node_id = find_dialogue_start_node(&dialogue)
                .map(|node| node.id.clone())
                .unwrap_or_else(|| "start".to_string());
            let target_name = viewer_state
                .current_prompt
                .as_ref()
                .map(|prompt| prompt.target_name.clone())
                .unwrap_or_else(|| dialog_id.clone());
            viewer_state.active_dialogue = Some(ActiveDialogueState {
                dialog_id: dialog_id.clone(),
                data: dialogue,
                current_node_id,
                target_name,
            });
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
        } else if let Some(dialog_id) = result.dialogue_id {
            format!("interaction: opened dialogue {}", dialog_id)
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
        "choice" => choice_index
            .and_then(|index| node.options.get(index))
            .map(|option| option.next.clone()),
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

fn load_dialogue(dialog_id: &str) -> Option<DialogueData> {
    let path = dialogue_path(dialog_id);
    let raw = fs::read_to_string(path).ok()?;
    serde_json::from_str(&raw).ok()
}

fn dialogue_path(dialog_id: &str) -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../../data/dialogues")
        .join(format!("{dialog_id}.json"))
}
