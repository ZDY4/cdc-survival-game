use bevy::prelude::*;
use game_bevy::SettlementDebugEntry;
use game_core::{ActorDebugState, SimulationSnapshot};
use game_data::InteractionPrompt;

use crate::dialogue::current_dialogue_node;
use crate::geometry::{
    actor_label, focused_target_summary, format_optional_grid, map_object_at_grid,
    movement_block_reasons, rendered_path_preview, selected_actor, sight_block_reasons,
};
use crate::state::{
    HudEventCategory, HudEventFilter, HudFooterText, HudText, ViewerEventEntry, ViewerHudPage,
    ViewerRuntimeState, ViewerState,
};

pub(crate) fn update_hud(
    hud_text: Single<(&mut Text, &mut Visibility), With<HudText>>,
    mut hud_footer: Single<&mut TextSpan, With<HudFooterText>>,
    runtime_state: Res<ViewerRuntimeState>,
    viewer_state: Res<ViewerState>,
) {
    let (mut hud_text, mut visibility) = hud_text.into_inner();
    if !viewer_state.show_hud {
        *visibility = Visibility::Hidden;
        *hud_text = Text::new("");
        **hud_footer = TextSpan::new("");
        return;
    }

    *visibility = Visibility::Visible;
    let snapshot = runtime_state.runtime.snapshot();
    let header = format!("Bevy Debug Viewer · {}", viewer_state.hud_page.title());
    let summary = format_status_summary(&snapshot, &runtime_state, &viewer_state);
    let page_body = match viewer_state.hud_page {
        ViewerHudPage::Overview => format_overview_panel(&snapshot, &runtime_state, &viewer_state),
        ViewerHudPage::SelectedActor => {
            format_selected_actor_panel(&snapshot, &runtime_state, &viewer_state)
        }
        ViewerHudPage::World => format_world_panel(&snapshot, &viewer_state),
        ViewerHudPage::Interaction => format_interaction_panel(&snapshot, &viewer_state),
        ViewerHudPage::Events => format_events_panel(&runtime_state, viewer_state.event_filter),
        ViewerHudPage::Ai => format_ai_panel(&runtime_state),
    };
    let controls = if viewer_state.show_controls {
        format!("\n\n{}", format_controls_help())
    } else {
        String::new()
    };

    *hud_text = Text::new(format!("{header}\n{}\n\n{page_body}{controls}", summary));
    **hud_footer = TextSpan::new(format!("\n\n{}", footer_hint(viewer_state.hud_page)));
}

fn actor_overview_summary(actor: &ActorDebugState) -> String {
    format!(
        "{} ({:?}, {:?})",
        actor_label(actor),
        actor.actor_id,
        actor.side
    )
}

fn format_status_summary(
    snapshot: &SimulationSnapshot,
    runtime_state: &ViewerRuntimeState,
    viewer_state: &ViewerState,
) -> String {
    section(
        "Status",
        vec![
            kv(
                "Status",
                if viewer_state.status_line.is_empty() {
                    "idle".to_string()
                } else {
                    viewer_state.status_line.clone()
                },
            ),
            kv("Control Mode", viewer_state.control_mode.label()),
            kv("Combat Active", snapshot.combat.in_combat),
            kv("Turn Index", snapshot.combat.current_turn_index),
            kv(
                "Pending Progression",
                format!("{:?}", runtime_state.runtime.peek_pending_progression()),
            ),
            kv(
                "Pending Movement",
                runtime_state.runtime.pending_movement().is_some(),
            ),
        ],
    )
}

fn format_overview_panel(
    snapshot: &SimulationSnapshot,
    runtime_state: &ViewerRuntimeState,
    viewer_state: &ViewerState,
) -> String {
    let selected = selected_actor(snapshot, viewer_state)
        .map(actor_overview_summary)
        .unwrap_or_else(|| "none".to_string());
    let recent_events: Vec<String> = runtime_state
        .recent_events
        .iter()
        .rev()
        .take(3)
        .map(|entry| {
            format!(
                "[{} t={}] {}",
                entry.category.label(),
                entry.turn_index,
                entry.text
            )
        })
        .collect::<Vec<_>>()
        .into_iter()
        .rev()
        .collect();

    let sections = vec![
        section(
            "Overview",
            vec![
                kv(
                    "Map",
                    snapshot
                        .grid
                        .map_id
                        .as_ref()
                        .map(|map_id| map_id.as_str())
                        .unwrap_or("none"),
                ),
                kv(
                    "Map Size",
                    format!(
                        "{}x{}",
                        snapshot.grid.map_width.unwrap_or(0),
                        snapshot.grid.map_height.unwrap_or(0)
                    ),
                ),
                kv("Current Level", viewer_state.current_level),
                kv("Combat", snapshot.combat.in_combat),
                kv(
                    "Current Actor",
                    format!("{:?}", snapshot.combat.current_actor_id),
                ),
                kv("Turn Index", snapshot.combat.current_turn_index),
            ],
        ),
        section(
            "Selection",
            vec![
                kv("Actor", selected),
                kv("Target", focused_target_summary(snapshot, viewer_state)),
            ],
        ),
        section(
            "Runtime",
            vec![
                kv(
                    "Pending Progression",
                    format!("{:?}", runtime_state.runtime.peek_pending_progression()),
                ),
                kv(
                    "Pending Movement",
                    runtime_state.runtime.pending_movement().is_some(),
                ),
                kv(
                    "Path Preview Cells",
                    rendered_path_preview(
                        &runtime_state.runtime,
                        snapshot,
                        runtime_state.runtime.pending_movement(),
                    )
                    .len(),
                ),
                kv(
                    "Hovered Grid",
                    format_optional_grid(viewer_state.hovered_grid),
                ),
                kv("Auto Tick", viewer_state.auto_tick),
            ],
        ),
        section(
            "Recent Events",
            if recent_events.is_empty() {
                vec!["none".to_string()]
            } else {
                recent_events
            },
        ),
    ];

    sections.join("\n\n")
}

fn format_selected_actor_panel(
    snapshot: &SimulationSnapshot,
    runtime_state: &ViewerRuntimeState,
    viewer_state: &ViewerState,
) -> String {
    let Some(actor) = selected_actor(snapshot, viewer_state) else {
        return section("Selected Actor", vec!["none".to_string()]);
    };

    let mut lines = vec![
        kv("Name", actor_label(actor)),
        kv("Kind", format!("{:?}", actor.kind)),
        kv("Side", format!("{:?}", actor.side)),
        kv(
            "Grid",
            format!(
                "({}, {}, {})",
                actor.grid_position.x, actor.grid_position.y, actor.grid_position.z
            ),
        ),
        kv("AP", format!("{:.1}", actor.ap)),
        kv("Steps", actor.available_steps),
        kv("Turn Open", actor.turn_open),
        kv("In Combat", actor.in_combat),
        kv(
            "Current Turn",
            snapshot.combat.current_actor_id == Some(actor.actor_id),
        ),
    ];

    if let Some(intent) = runtime_state.runtime.pending_movement() {
        if intent.actor_id == actor.actor_id {
            let pending_path = rendered_path_preview(
                &runtime_state.runtime,
                snapshot,
                runtime_state.runtime.pending_movement(),
            );
            lines.push(kv(
                "Pending Move Goal",
                format!(
                    "({}, {}, {})",
                    intent.requested_goal.x, intent.requested_goal.y, intent.requested_goal.z
                ),
            ));
            lines.push(kv("Pending Move Path Cells", pending_path.len()));
        } else {
            lines.push(kv("Pending Move", "other actor"));
        }
    } else {
        lines.push(kv("Pending Move", "none"));
    }

    if let Some(entry) = selected_actor_ai_entry(actor, runtime_state) {
        lines.push(String::new());
        lines.push("AI Runtime:".to_string());
        lines.extend(format_selected_ai_lines(entry));
    }

    section("Selected Actor", lines)
}

fn format_world_panel(snapshot: &SimulationSnapshot, viewer_state: &ViewerState) -> String {
    let level = viewer_state.current_level;
    let actor_count = snapshot
        .actors
        .iter()
        .filter(|actor| actor.grid_position.y == level)
        .count();
    let object_count = snapshot
        .grid
        .map_objects
        .iter()
        .filter(|object| object.anchor.y == level)
        .count();
    let static_obstacle_count = snapshot
        .grid
        .static_obstacles
        .iter()
        .filter(|grid| grid.y == level)
        .count();
    let runtime_blocked_count = snapshot
        .grid
        .runtime_blocked_cells
        .iter()
        .filter(|grid| grid.y == level)
        .count();

    let mut sections = vec![
        section(
            "World",
            vec![
                kv(
                    "Map",
                    snapshot
                        .grid
                        .map_id
                        .as_ref()
                        .map(|map_id| map_id.as_str())
                        .unwrap_or("none"),
                ),
                kv(
                    "Map Size",
                    format!(
                        "{}x{}",
                        snapshot.grid.map_width.unwrap_or(0),
                        snapshot.grid.map_height.unwrap_or(0)
                    ),
                ),
                kv("Current Level", level),
                kv("Actors On Level", actor_count),
                kv("Objects On Level", object_count),
                kv("Static Obstacles On Level", static_obstacle_count),
                kv("Runtime Blocked On Level", runtime_blocked_count),
            ],
        ),
        format_hover_section(snapshot, viewer_state),
    ];

    if let Some(grid) = viewer_state.hovered_grid {
        if let Some(object) = map_object_at_grid(snapshot, grid) {
            sections.push(section(
                "Hovered Object",
                vec![
                    kv("Id", &object.object_id),
                    kv("Kind", format!("{:?}", object.kind)),
                    kv(
                        "Anchor",
                        format!(
                            "({}, {}, {})",
                            object.anchor.x, object.anchor.y, object.anchor.z
                        ),
                    ),
                    kv("Blocks Movement", object.blocks_movement),
                    kv("Blocks Sight", object.blocks_sight),
                    kv("Payload", format_payload_summary(&object.payload_summary)),
                ],
            ));
        }
    }

    sections.join("\n\n")
}

fn format_hover_section(snapshot: &SimulationSnapshot, viewer_state: &ViewerState) -> String {
    let Some(grid) = viewer_state.hovered_grid else {
        return section("Hover Cell", vec!["none".to_string()]);
    };

    let cell = snapshot
        .grid
        .map_cells
        .iter()
        .find(|cell| cell.grid == grid);
    let actors = snapshot
        .actors
        .iter()
        .filter(|actor| actor.grid_position == grid)
        .map(|actor| format!("{} ({:?})", actor_label(actor), actor.side))
        .collect::<Vec<_>>();
    let objects = snapshot
        .grid
        .map_objects
        .iter()
        .filter(|object| object.occupied_cells.contains(&grid))
        .map(|object| format!("{} ({:?})", object.object_id, object.kind))
        .collect::<Vec<_>>();
    let movement_reasons = movement_block_reasons(snapshot, grid);
    let sight_reasons = sight_block_reasons(snapshot, grid);

    section(
        "Hover Cell",
        vec![
            kv("Grid", format!("({}, {}, {})", grid.x, grid.y, grid.z)),
            kv(
                "Terrain",
                cell.map(|entry| entry.terrain.as_str()).unwrap_or("none"),
            ),
            kv(
                "Movement",
                if movement_reasons.is_empty() {
                    "walkable".to_string()
                } else {
                    format!("blocked_by {}", movement_reasons.join(", "))
                },
            ),
            kv(
                "Sight",
                if sight_reasons.is_empty() {
                    "clear".to_string()
                } else {
                    format!("blocked_by {}", sight_reasons.join(", "))
                },
            ),
            kv("Actors", format_string_list(&actors)),
            kv("Objects", format_string_list(&objects)),
        ],
    )
}

fn format_interaction_panel(snapshot: &SimulationSnapshot, viewer_state: &ViewerState) -> String {
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

fn format_dialogue_section(dialogue: Option<&crate::state::ActiveDialogueState>) -> String {
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

fn format_events_panel(runtime_state: &ViewerRuntimeState, event_filter: HudEventFilter) -> String {
    let events: Vec<String> = runtime_state
        .recent_events
        .iter()
        .filter(|entry| event_matches_filter(entry, event_filter))
        .rev()
        .take(20)
        .map(format_event_line)
        .collect::<Vec<_>>()
        .into_iter()
        .rev()
        .collect();

    section(
        "Events",
        if events.is_empty() {
            vec![kv("Filter", event_filter.label()), kv("Visible", 0)]
        } else {
            std::iter::once(kv("Filter", event_filter.label()))
                .chain(std::iter::once(kv("Visible", events.len())))
                .chain(events)
                .collect()
        },
    )
}

fn format_ai_panel(runtime_state: &ViewerRuntimeState) -> String {
    let snapshot = &runtime_state.ai_snapshot;
    if snapshot.entries.is_empty() {
        return section("AI", vec!["no settlement AI entries".to_string()]);
    }

    let mut lines = vec![kv("Entries", snapshot.entries.len())];
    for (index, entry) in snapshot.entries.iter().take(6).enumerate() {
        let top_scores = entry
            .goal_scores
            .iter()
            .take(3)
            .map(|score| format!("{:?}:{}", score.goal, score.score))
            .collect::<Vec<_>>()
            .join(", ");
        lines.push(format!("Entry {}:", index + 1));
        lines.push(kv("  Role", format!("{:?}", entry.role)));
        lines.push(kv("  Goal", format!("{:?}", entry.goal)));
        lines.push(kv("  Action", format!("{:?}", entry.action)));
        lines.push(kv("  Failure", format!("{:?}", entry.last_failure_reason)));
        lines.push(kv("  Top Scores", top_scores));
        lines.push(kv("  Summary", entry.decision_summary.clone()));
    }

    section("AI", lines)
}

fn selected_actor_ai_entry<'a>(
    actor: &ActorDebugState,
    runtime_state: &'a ViewerRuntimeState,
) -> Option<&'a SettlementDebugEntry> {
    runtime_state
        .ai_snapshot
        .entries
        .iter()
        .find(|entry| entry.runtime_actor_id == Some(actor.actor_id))
        .or_else(|| {
            actor.definition_id.as_ref().and_then(|definition_id| {
                runtime_state
                    .ai_snapshot
                    .entries
                    .iter()
                    .find(|entry| entry.definition_id == definition_id.as_str())
            })
        })
}

fn format_selected_ai_lines(entry: &SettlementDebugEntry) -> Vec<String> {
    vec![
        kv("  Role", format!("{:?}", entry.role)),
        kv("  Goal", format!("{:?}", entry.goal)),
        kv("  Action", format!("{:?}", entry.action)),
        kv("  Failure", format!("{:?}", entry.last_failure_reason)),
        kv(
            "  Top Scores",
            entry
                .goal_scores
                .iter()
                .take(3)
                .map(|score| format!("{:?}:{}", score.goal, score.score))
                .collect::<Vec<_>>()
                .join(", "),
        ),
        kv("  Summary", entry.decision_summary.clone()),
    ]
}

fn format_controls_help() -> String {
    section(
        "Controls",
        vec![
            "F1-F6 switch HUD page".to_string(),
            "Ctrl+P toggle player control / free observe".to_string(),
            "H toggle HUD".to_string(),
            "/ toggle detailed help".to_string(),
            "[ / ] switch event filter on Events page".to_string(),
            "Left click cancels auto-move, selects actor, advances dialogue, or moves".to_string(),
            "Right click target opens the interaction button menu".to_string(),
            "Mouse click triggers scene interactions".to_string(),
            "1-9 choose dialogue choice".to_string(),
            "Space / Enter advance dialogue".to_string(),
            "Esc close dialogue".to_string(),
            "Space cancels auto-move, otherwise ends turn (hold to repeat)".to_string(),
            "Middle mouse drag pans camera".to_string(),
            "Mouse wheel zooms".to_string(),
            "F recenter camera".to_string(),
            "PageUp/PageDown change level".to_string(),
            "Tab cycle actor on current level".to_string(),
            "A toggle auto tick".to_string(),
            "= zoom in, - zoom out, 0 reset zoom".to_string(),
        ],
    )
}

pub(crate) fn footer_hint(page: ViewerHudPage) -> &'static str {
    match page {
        ViewerHudPage::Overview => {
            "F1-6切页 · Ctrl+P控制/观察切换 · H隐藏HUD · /帮助 · A自动推进 · PgUp/Dn楼层 · Tab切换角色"
        }
        ViewerHudPage::SelectedActor => {
            "F1-6切页 · Ctrl+P控制/观察切换 · H隐藏HUD · /帮助 · Tab切换角色 · 自由观察下左键选AI"
        }
        ViewerHudPage::World => {
            "F1-6切页 · Ctrl+P控制/观察切换 · H隐藏HUD · /帮助 · 悬停看格子 · 中键拖拽 · 滚轮缩放 · F回中"
        }
        ViewerHudPage::Interaction => {
            "F1-6切页 · Ctrl+P控制/观察切换 · H隐藏HUD · /帮助 · 左键主交互 · 右键开菜单 · 点击按钮执行交互 · 1-9选对话分支"
        }
        ViewerHudPage::Events => "F1-6切页 · Ctrl+P控制/观察切换 · H隐藏HUD · /帮助 · [ / ]切过滤器",
        ViewerHudPage::Ai => "F1-6切页 · Ctrl+P控制/观察切换 · H隐藏HUD · /帮助 · 查看 AI 目标 / 动作 / 预订 / 班次",
    }
}

fn section(title: &str, lines: Vec<String>) -> String {
    let mut text = String::from(title);
    for line in lines {
        text.push_str("\n  ");
        text.push_str(&line);
    }
    text
}

fn kv(label: &str, value: impl std::fmt::Display) -> String {
    format!("{label}: {value}")
}

fn format_string_list(values: &[String]) -> String {
    if values.is_empty() {
        "none".to_string()
    } else {
        values.join(", ")
    }
}

pub(crate) fn format_event_line(entry: &ViewerEventEntry) -> String {
    format!(
        "{} · t={} · {}",
        event_badge(entry.category),
        entry.turn_index,
        entry.text
    )
}

fn event_badge(category: HudEventCategory) -> &'static str {
    match category {
        HudEventCategory::Combat => "COMBAT",
        HudEventCategory::Interaction => "INTERACT",
        HudEventCategory::World => "WORLD",
    }
}

fn format_payload_summary(payload_summary: &std::collections::BTreeMap<String, String>) -> String {
    if payload_summary.is_empty() {
        "none".to_string()
    } else {
        payload_summary
            .iter()
            .map(|(key, value)| format!("{key}={value}"))
            .collect::<Vec<_>>()
            .join(", ")
    }
}

fn compact_text(text: &str) -> String {
    let trimmed = text.trim();
    if trimmed.is_empty() {
        "none".to_string()
    } else {
        trimmed.replace('\n', " / ")
    }
}

pub(crate) fn event_matches_filter(event: &ViewerEventEntry, filter: HudEventFilter) -> bool {
    match filter {
        HudEventFilter::All => true,
        HudEventFilter::Combat => event.category == HudEventCategory::Combat,
        HudEventFilter::Interaction => event.category == HudEventCategory::Interaction,
        HudEventFilter::World => event.category == HudEventCategory::World,
    }
}

#[cfg(test)]
mod tests {
    use super::{event_matches_filter, footer_hint, format_event_line};
    use crate::simulation::classify_event;
    use crate::state::{HudEventCategory, HudEventFilter, ViewerEventEntry, ViewerHudPage};
    use game_core::SimulationEvent;
    use game_data::{ActorId, InteractionTargetId};

    #[test]
    fn footer_hint_contains_global_shortcuts_and_page_specific_action() {
        let overview_hint = footer_hint(ViewerHudPage::Overview);
        let events_hint = footer_hint(ViewerHudPage::Events);

        assert!(overview_hint.contains("F1-6切页"));
        assert!(overview_hint.contains("A自动推进"));
        assert!(events_hint.contains("切过滤器"));
    }

    #[test]
    fn event_filter_matches_expected_categories() {
        let combat = ViewerEventEntry {
            category: classify_event(&SimulationEvent::CombatStateChanged { in_combat: true }),
            turn_index: 3,
            text: "combat state -> true".to_string(),
        };
        let interaction = ViewerEventEntry {
            category: classify_event(&SimulationEvent::DialogueStarted {
                actor_id: ActorId(1),
                target_id: InteractionTargetId::MapObject("door".into()),
                dialogue_id: "intro".into(),
            }),
            turn_index: 3,
            text: "dialogue started".to_string(),
        };

        assert_eq!(combat.category, HudEventCategory::Combat);
        assert!(event_matches_filter(&combat, HudEventFilter::Combat));
        assert!(!event_matches_filter(&combat, HudEventFilter::Interaction));

        assert_eq!(interaction.category, HudEventCategory::Interaction);
        assert!(event_matches_filter(
            &interaction,
            HudEventFilter::Interaction
        ));
        assert!(event_matches_filter(&interaction, HudEventFilter::All));
    }

    #[test]
    fn formatted_event_line_starts_with_category_badge() {
        let entry = ViewerEventEntry {
            category: HudEventCategory::World,
            turn_index: 12,
            text: "world cycle completed".into(),
        };

        let line = format_event_line(&entry);
        assert!(line.starts_with("WORLD"));
        assert!(line.contains("t=12"));
    }
}
