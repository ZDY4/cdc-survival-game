use game_core::SimulationSnapshot;
use game_data::InteractionPrompt;

use crate::dialogue::current_dialogue_node;
use crate::geometry::focused_target_summary;
use crate::state::{ActiveDialogueState, ViewerState};

use super::{compact_text, kv, section};

pub(crate) fn format_interaction_panel(
    snapshot: &SimulationSnapshot,
    viewer_state: &ViewerState,
) -> String {
    let mut sections = vec![
        section(
            "Focused Target",
            vec![kv("Target", focused_target_summary(snapshot, viewer_state))],
        ),
        format_prompt_section(viewer_state.current_prompt.as_ref()),
        format_dialogue_section(viewer_state.active_dialogue.as_ref()),
        section(
            "Interaction Context",
            vec![
                kv(
                    "Mode",
                    format!("{:?}", snapshot.interaction_context.world_mode),
                ),
                kv(
                    "Map",
                    snapshot
                        .interaction_context
                        .current_map_id
                        .as_deref()
                        .unwrap_or("none"),
                ),
            ],
        ),
    ];
    sections.retain(|section| !section.is_empty());
    sections.join("\n\n")
}

fn format_prompt_section(prompt: Option<&InteractionPrompt>) -> String {
    let Some(prompt) = prompt else {
        return section("Prompt", vec!["none".to_string()]);
    };

    let mut lines = vec![
        kv("Target Name", prompt.target_name.clone()),
        kv(
            "Primary Option",
            prompt
                .primary_option_id
                .as_ref()
                .map(|id| id.0.as_str())
                .unwrap_or("none"),
        ),
    ];

    if prompt.options.is_empty() {
        lines.push(kv("Options", "none"));
    } else {
        lines.push(kv("Option Count", prompt.options.len()));
        lines.extend(prompt.options.iter().enumerate().map(|(index, option)| {
            format!(
                "Option {}: {} | kind={:?} | danger={} | prox={} | dist={:.1} | pri={}{}",
                index + 1,
                option.display_name,
                option.kind,
                option.dangerous,
                option.requires_proximity,
                option.interaction_distance,
                option.priority,
                if prompt.primary_option_id.as_ref() == Some(&option.id) {
                    " primary"
                } else {
                    ""
                }
            )
        }));
    }

    section("Prompt", lines)
}

fn format_dialogue_section(dialogue: Option<&ActiveDialogueState>) -> String {
    let Some(dialogue) = dialogue else {
        return section("Dialogue", vec!["inactive".to_string()]);
    };
    let Some(node) = current_dialogue_node(dialogue) else {
        return section(
            "Dialogue",
            vec![format!(
                "invalid node dialog_id={} node_id={}",
                dialogue.dialog_id, dialogue.current_node_id
            )],
        );
    };

    let mut lines = vec![
        kv("Target", dialogue.target_name.clone()),
        kv(
            "Speaker",
            if node.speaker.trim().is_empty() {
                "none".to_string()
            } else {
                node.speaker.clone()
            },
        ),
        kv("Text", compact_text(&node.text)),
    ];

    if node.options.is_empty() {
        lines.push(kv("Choices", "none"));
    } else {
        lines.push(kv("Choices", node.options.len()));
        lines.extend(
            node.options
                .iter()
                .enumerate()
                .map(|(index, option)| format!("{}. {}", index + 1, compact_text(&option.text))),
        );
    }

    section("Dialogue", lines)
}
