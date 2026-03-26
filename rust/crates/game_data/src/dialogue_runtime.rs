use serde::{Deserialize, Serialize};

use crate::{
    ActorId, DialogueAction, DialogueData, DialogueNode, DialogueOption, InteractionTargetId,
};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct DialogueSessionState {
    pub actor_id: ActorId,
    #[serde(default)]
    pub target_id: Option<InteractionTargetId>,
    #[serde(default)]
    pub dialogue_key: String,
    #[serde(default)]
    pub dialogue_id: String,
    #[serde(default)]
    pub current_node_id: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct DialogueRuntimeState {
    pub session: DialogueSessionState,
    #[serde(default)]
    pub current_node: Option<DialogueNode>,
    #[serde(default)]
    pub available_options: Vec<DialogueOption>,
    #[serde(default)]
    pub finished: bool,
    #[serde(default)]
    pub end_type: Option<String>,
    #[serde(default)]
    pub emitted_actions: Vec<DialogueAction>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum DialogueAdvanceError {
    MissingNode {
        node_id: String,
    },
    ChoiceRequired {
        node_id: String,
    },
    InvalidChoice {
        node_id: String,
        choice_index: usize,
    },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Default)]
pub struct DialogueAdvanceOutcome {
    #[serde(default)]
    pub next_node_id: Option<String>,
    #[serde(default)]
    pub finished: bool,
    #[serde(default)]
    pub emitted_actions: Vec<DialogueAction>,
    #[serde(default)]
    pub end_type: Option<String>,
}

pub fn current_dialogue_node<'a>(
    dialogue: &'a DialogueData,
    node_id: &str,
) -> Option<&'a DialogueNode> {
    dialogue.nodes.iter().find(|node| node.id == node_id)
}

pub fn find_dialogue_start_node(dialogue: &DialogueData) -> Option<&DialogueNode> {
    dialogue
        .nodes
        .iter()
        .find(|node| node.is_start)
        .or_else(|| dialogue.nodes.first())
}

pub fn resolve_dialogue_start_node_id(dialogue: &DialogueData) -> Option<String> {
    find_dialogue_start_node(dialogue).map(|node| node.id.clone())
}

pub fn advance_dialogue(
    dialogue: &DialogueData,
    current_node_id: &str,
    choice_index: Option<usize>,
) -> Result<DialogueAdvanceOutcome, DialogueAdvanceError> {
    let node = current_dialogue_node(dialogue, current_node_id).ok_or_else(|| {
        DialogueAdvanceError::MissingNode {
            node_id: current_node_id.to_string(),
        }
    })?;

    let next_node_id = match node.node_type.as_str() {
        "choice" => {
            let Some(choice_index) = choice_index else {
                return Err(DialogueAdvanceError::ChoiceRequired {
                    node_id: node.id.clone(),
                });
            };
            let Some(option) = node.options.get(choice_index) else {
                return Err(DialogueAdvanceError::InvalidChoice {
                    node_id: node.id.clone(),
                    choice_index,
                });
            };
            normalized_next_node_id(option.next.as_str())
        }
        "end" => None,
        _ => normalized_next_node_id(node.next.as_str()),
    };

    Ok(DialogueAdvanceOutcome {
        finished: next_node_id.is_none(),
        next_node_id,
        emitted_actions: node.actions.clone(),
        end_type: normalized_next_node_id(node.end_type.as_str()),
    })
}

pub fn dialogue_runtime_state(
    dialogue: &DialogueData,
    session: DialogueSessionState,
    emitted_actions: Vec<DialogueAction>,
    finished: bool,
    end_type: Option<String>,
) -> DialogueRuntimeState {
    let current_node = current_dialogue_node(dialogue, &session.current_node_id).cloned();
    let available_options = current_node
        .as_ref()
        .map(|node| node.options.clone())
        .unwrap_or_default();
    DialogueRuntimeState {
        session,
        current_node,
        available_options,
        finished,
        end_type,
        emitted_actions,
    }
}

fn normalized_next_node_id(value: &str) -> Option<String> {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        None
    } else {
        Some(trimmed.to_string())
    }
}

#[cfg(test)]
mod tests {
    use super::{
        advance_dialogue, current_dialogue_node, dialogue_runtime_state, find_dialogue_start_node,
        resolve_dialogue_start_node_id, DialogueAdvanceError, DialogueAdvanceOutcome,
        DialogueSessionState,
    };
    use crate::{ActorId, DialogueData, DialogueNode, DialogueOption, InteractionTargetId};

    #[test]
    fn start_node_prefers_explicit_start_flag() {
        let dialogue = sample_dialogue();

        let start = find_dialogue_start_node(&dialogue).expect("start node should exist");

        assert_eq!(start.id, "start");
        assert_eq!(
            resolve_dialogue_start_node_id(&dialogue).as_deref(),
            Some("start")
        );
    }

    #[test]
    fn current_node_lookup_finds_matching_node() {
        let dialogue = sample_dialogue();

        let node = current_dialogue_node(&dialogue, "choice").expect("choice node should exist");

        assert_eq!(node.node_type, "choice");
    }

    #[test]
    fn choice_node_requires_explicit_selection() {
        let dialogue = sample_dialogue();

        let error = advance_dialogue(&dialogue, "choice", None)
            .expect_err("choice node should require explicit selection");

        assert_eq!(
            error,
            DialogueAdvanceError::ChoiceRequired {
                node_id: "choice".into(),
            }
        );
    }

    #[test]
    fn choice_node_advances_to_selected_option() {
        let dialogue = sample_dialogue();

        let outcome = advance_dialogue(&dialogue, "choice", Some(1))
            .expect("valid choice should advance dialogue");

        assert_eq!(
            outcome,
            DialogueAdvanceOutcome {
                next_node_id: Some("accept".into()),
                finished: false,
                emitted_actions: Vec::new(),
                end_type: None,
            }
        );
    }

    #[test]
    fn terminal_node_marks_dialogue_finished() {
        let dialogue = sample_dialogue();

        let outcome =
            advance_dialogue(&dialogue, "accept", None).expect("terminal node should resolve");

        assert_eq!(
            outcome,
            DialogueAdvanceOutcome {
                next_node_id: None,
                finished: true,
                emitted_actions: Vec::new(),
                end_type: None,
            }
        );
    }

    #[test]
    fn runtime_state_exposes_current_node_and_options() {
        let dialogue = sample_dialogue();
        let state = dialogue_runtime_state(
            &dialogue,
            DialogueSessionState {
                actor_id: ActorId(1),
                target_id: Some(InteractionTargetId::MapObject("npc".into())),
                dialogue_key: "sample".into(),
                dialogue_id: "sample".into(),
                current_node_id: "choice".into(),
            },
            Vec::new(),
            false,
            None,
        );

        assert_eq!(state.available_options.len(), 2);
        assert_eq!(
            state.current_node.as_ref().map(|node| node.id.as_str()),
            Some("choice")
        );
    }

    fn sample_dialogue() -> DialogueData {
        DialogueData {
            dialog_id: "sample".into(),
            nodes: vec![
                DialogueNode {
                    id: "start".into(),
                    node_type: "dialog".into(),
                    is_start: true,
                    next: "choice".into(),
                    ..DialogueNode::default()
                },
                DialogueNode {
                    id: "choice".into(),
                    node_type: "choice".into(),
                    options: vec![
                        DialogueOption {
                            text: "Decline".into(),
                            next: "end".into(),
                            ..DialogueOption::default()
                        },
                        DialogueOption {
                            text: "Accept".into(),
                            next: "accept".into(),
                            ..DialogueOption::default()
                        },
                    ],
                    ..DialogueNode::default()
                },
                DialogueNode {
                    id: "accept".into(),
                    node_type: "dialog".into(),
                    ..DialogueNode::default()
                },
                DialogueNode {
                    id: "end".into(),
                    node_type: "end".into(),
                    ..DialogueNode::default()
                },
            ],
            ..DialogueData::default()
        }
    }
}
