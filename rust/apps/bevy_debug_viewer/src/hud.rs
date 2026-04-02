use bevy::diagnostic::DiagnosticsStore;
use bevy::prelude::*;
use game_bevy::SettlementDebugEntry;
use game_core::{ActorDebugState, SimulationSnapshot};
use game_data::InteractionPrompt;

use crate::dialogue::current_dialogue_node;
use crate::geometry::{
    actor_label, focused_target_summary, format_optional_grid, is_missing_generated_building,
    map_object_at_grid, map_object_debug_label, movement_block_reasons, rendered_path_preview,
    selected_actor, sight_block_reasons,
};
use crate::profiling::ViewerSystemProfilerState;
use crate::state::{
    FpsOverlayText, FreeObserveIndicatorRoot, HudFooterText, HudTabBarRoot, HudTabButton, HudText,
    ViewerHudPage, ViewerRenderConfig, ViewerRuntimeState, ViewerSceneKind, ViewerState,
};
use game_bevy::{UiMenuPanel, UiMenuState};

mod events;
mod footer;
mod performance;
mod tabs;

use events::format_events_panel;
use footer::footer_hint;
use performance::{current_fps_label, format_performance_panel};
use tabs::{hud_tab_button_border_color, hud_tab_button_color};

pub(crate) fn update_free_observe_indicator(
    indicator_visibility: Single<&mut Visibility, With<FreeObserveIndicatorRoot>>,
    scene_kind: Res<ViewerSceneKind>,
    viewer_state: Res<ViewerState>,
    menu_state: Res<UiMenuState>,
) {
    let mut indicator_visibility = indicator_visibility.into_inner();
    *indicator_visibility = if scene_kind.is_gameplay()
        && viewer_state.is_free_observe()
        && menu_state.active_panel != Some(UiMenuPanel::Settings)
    {
        Visibility::Visible
    } else {
        Visibility::Hidden
    };
}

pub(crate) fn update_hud(
    hud_text: Single<(&mut Text, &mut Visibility), With<HudText>>,
    mut hud_footer: Single<&mut TextSpan, With<HudFooterText>>,
    profiler: Res<ViewerSystemProfilerState>,
    runtime_state: Res<ViewerRuntimeState>,
    render_config: Res<ViewerRenderConfig>,
    scene_kind: Res<ViewerSceneKind>,
    viewer_state: Res<ViewerState>,
    menu_state: Res<UiMenuState>,
) {
    let (mut hud_text, mut visibility) = hud_text.into_inner();
    if scene_kind.is_main_menu()
        || !viewer_state.show_hud
        || menu_state.active_panel == Some(UiMenuPanel::Settings)
    {
        *visibility = Visibility::Hidden;
        *hud_text = Text::new("");
        **hud_footer = TextSpan::new("");
        return;
    }

    *visibility = Visibility::Visible;
    let snapshot = runtime_state.runtime.snapshot();
    let header = format!("Bevy Debug Viewer · {}", viewer_state.hud_page.title());
    let summary = format_status_summary(&snapshot, &runtime_state, &viewer_state, *render_config);
    let page_body = match viewer_state.hud_page {
        ViewerHudPage::Overview => format_overview_panel(&snapshot, &runtime_state, &viewer_state),
        ViewerHudPage::SelectedActor => {
            format_selected_actor_panel(&snapshot, &runtime_state, &viewer_state)
        }
        ViewerHudPage::World => format_world_panel(&snapshot, &viewer_state),
        ViewerHudPage::Interaction => format_interaction_panel(&snapshot, &viewer_state),
        ViewerHudPage::Events => format_events_panel(&runtime_state, viewer_state.event_filter),
        ViewerHudPage::Ai => format_ai_panel(&runtime_state),
        ViewerHudPage::Performance => format_performance_panel(&profiler),
    };
    let controls = if viewer_state.show_controls {
        format!("\n\n{}", format_controls_help())
    } else {
        String::new()
    };

    *hud_text = Text::new(format!("{header}\n{}\n\n{page_body}{controls}", summary));
    **hud_footer = TextSpan::new(format!("\n\n{}", footer_hint(viewer_state.hud_page)));
}

pub(crate) fn update_hud_tab_bar(
    tab_bar_visibility: Single<&mut Visibility, With<HudTabBarRoot>>,
    mut tab_buttons: Query<
        (
            &Interaction,
            &mut BackgroundColor,
            &mut BorderColor,
            &mut TextColor,
            &HudTabButton,
        ),
        With<HudTabButton>,
    >,
    scene_kind: Res<ViewerSceneKind>,
    viewer_state: Res<ViewerState>,
    menu_state: Res<UiMenuState>,
) {
    let hidden = scene_kind.is_main_menu()
        || !viewer_state.show_hud
        || menu_state.active_panel == Some(UiMenuPanel::Settings);
    let mut tab_bar_visibility = tab_bar_visibility.into_inner();
    *tab_bar_visibility = if hidden {
        Visibility::Hidden
    } else {
        Visibility::Visible
    };
    if hidden {
        return;
    }

    for (interaction, mut background, mut border, mut text_color, tab_button) in &mut tab_buttons {
        let is_selected = viewer_state.hud_page == tab_button.page;
        *background = BackgroundColor(hud_tab_button_color(is_selected, *interaction));
        *border = BorderColor::all(hud_tab_button_border_color(is_selected));
        *text_color = TextColor(if is_selected {
            Color::srgba(0.98, 0.99, 1.0, 1.0)
        } else {
            Color::srgba(0.85, 0.88, 0.93, 0.98)
        });
    }
}

pub(crate) fn handle_hud_tab_buttons(
    mut tab_buttons: Query<
        (&Interaction, &HudTabButton),
        (Changed<Interaction>, With<HudTabButton>),
    >,
    mut viewer_state: ResMut<ViewerState>,
    scene_kind: Res<ViewerSceneKind>,
    menu_state: Res<UiMenuState>,
) {
    if scene_kind.is_main_menu() || menu_state.active_panel == Some(UiMenuPanel::Settings) {
        return;
    }

    for (interaction, tab_button) in &mut tab_buttons {
        if *interaction != Interaction::Pressed {
            continue;
        }
        set_hud_page(&mut viewer_state, tab_button.page);
    }
}

pub(crate) fn update_fps_overlay(
    fps_overlay: Single<(&mut Text, &mut Visibility), With<FpsOverlayText>>,
    diagnostics: Res<DiagnosticsStore>,
    scene_kind: Res<ViewerSceneKind>,
    viewer_state: Res<ViewerState>,
) {
    let (mut fps_overlay, mut visibility) = fps_overlay.into_inner();
    if scene_kind.is_main_menu() || !viewer_state.show_fps_overlay {
        *visibility = Visibility::Hidden;
        *fps_overlay = Text::new("");
        return;
    }

    *visibility = Visibility::Visible;
    *fps_overlay = Text::new(format!("FPS {}", current_fps_label(&diagnostics)));
}

pub(crate) fn set_hud_page(viewer_state: &mut ViewerState, page: ViewerHudPage) {
    viewer_state.hud_page = page;
    viewer_state.status_line = format!("hud page: {}", page.title());
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
    render_config: ViewerRenderConfig,
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
            kv("Camera Mode", viewer_state.camera_mode.label()),
            kv("Combat Active", snapshot.combat.in_combat),
            kv("Combat Turn Index", combat_turn_index_label(snapshot)),
            kv("Runtime Tick", runtime_state.runtime.tick_count()),
            kv(
                "Pending Progression",
                format!("{:?}", runtime_state.runtime.peek_pending_progression()),
            ),
            kv(
                "Pending Movement",
                runtime_state.runtime.pending_movement().is_some(),
            ),
            kv("Overlay", render_config.overlay_mode.label()),
            kv("Zoom", format!("{:.0}%", render_config.zoom_factor * 100.0)),
        ],
    )
}

fn combat_turn_index_label(snapshot: &SimulationSnapshot) -> String {
    if snapshot.combat.in_combat {
        // Render 1-based turn numbers for the HUD while combat is active.
        snapshot
            .combat
            .current_turn_index
            .saturating_add(1)
            .to_string()
    } else {
        "inactive".to_string()
    }
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
                kv("Combat Turn Index", combat_turn_index_label(snapshot)),
                kv("Runtime Tick", runtime_state.runtime.tick_count()),
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
            let mut lines = vec![
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
            ];
            if is_missing_generated_building(snapshot, &object) {
                lines.push(kv("Geo", "missing geo"));
            }
            sections.push(section("Hovered Object", lines));
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
        .map(|object| map_object_debug_label(snapshot, object))
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
            .map(|score| {
                if score.matched_rule_ids.is_empty() {
                    format!("{:?}:{}", score.goal, score.score)
                } else {
                    format!(
                        "{:?}:{} ({})",
                        score.goal,
                        score.score,
                        score.matched_rule_ids.join("+")
                    )
                }
            })
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
                .map(|score| {
                    if score.matched_rule_ids.is_empty() {
                        format!("{:?}:{}", score.goal, score.score)
                    } else {
                        format!(
                            "{:?}:{} ({})",
                            score.goal,
                            score.score,
                            score.matched_rule_ids.join("+")
                        )
                    }
                })
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
            "F1-F7 switch HUD page".to_string(),
            "Ctrl+P toggle player control / free observe".to_string(),
            "H toggle HUD".to_string(),
            "/ toggle detailed help".to_string(),
            "~ toggle debug console".to_string(),
            "Console command: show fps toggles top-right FPS overlay".to_string(),
            "V cycles overlay density (minimal / gameplay / AI debug)".to_string(),
            "[ / ] switch event filter on Events page".to_string(),
            "Left click cancels auto-move, selects actor, advances dialogue, or moves".to_string(),
            "Right click target opens the interaction button menu".to_string(),
            "Mouse click triggers scene interactions".to_string(),
            "1-9 choose dialogue choice".to_string(),
            "Space / Enter advance dialogue".to_string(),
            "Esc close dialogue".to_string(),
            "Space cancels auto-move, otherwise ends turn (hold to repeat)".to_string(),
            "Middle mouse drag switches camera to manual pan".to_string(),
            "Mouse wheel zooms".to_string(),
            "F resumes follow camera on selected actor".to_string(),
            "PageUp/PageDown change level".to_string(),
            "Tab cycle actor on current level".to_string(),
            "A toggle auto tick".to_string(),
            "= zoom in, - zoom out, 0 reset zoom".to_string(),
        ],
    )
}

pub(crate) fn section(title: &str, lines: Vec<String>) -> String {
    let mut text = String::from(title);
    for line in lines {
        text.push_str("\n  ");
        text.push_str(&line);
    }
    text
}

pub(crate) fn kv(label: &str, value: impl std::fmt::Display) -> String {
    format!("{label}: {value}")
}

fn format_string_list(values: &[String]) -> String {
    if values.is_empty() {
        "none".to_string()
    } else {
        values.join(", ")
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

#[cfg(test)]
mod tests {
    use crate::hud::events::{event_matches_filter, format_event_line};
    use crate::hud::footer::footer_hint;
    use crate::hud::performance::{
        format_fps_value, format_frame_timings_section, format_performance_panel,
    };
    use crate::hud::tabs::hud_tab_button_color;
    use crate::profiling::ViewerSystemProfilerState;
    use crate::simulation::classify_event;
    use crate::state::{HudEventCategory, HudEventFilter, ViewerEventEntry, ViewerHudPage};
    use bevy::prelude::Interaction;
    use game_core::SimulationEvent;
    use game_data::{ActorId, InteractionTargetId};

    #[test]
    fn footer_hint_contains_global_shortcuts_and_page_specific_action() {
        let overview_hint = footer_hint(ViewerHudPage::Overview);
        let events_hint = footer_hint(ViewerHudPage::Events);
        let perf_hint = footer_hint(ViewerHudPage::Performance);

        assert!(overview_hint.contains("F1-7切页"));
        assert!(overview_hint.contains("show fps"));
        assert!(events_hint.contains("切换事件过滤"));
        assert!(perf_hint.contains("show fps"));
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

    #[test]
    fn format_fps_value_falls_back_when_no_samples_exist() {
        assert_eq!(format_fps_value(None), "--");
    }

    #[test]
    fn format_fps_value_formats_integer() {
        assert_eq!(format_fps_value(Some(59.94)), "60");
    }

    #[test]
    fn frame_timings_section_lists_hottest_systems() {
        let mut profiler = ViewerSystemProfilerState::default();
        profiler.record_sample("draw_world", 4.0);
        profiler.record_sample("tick_runtime", 1.5);

        let section = format_frame_timings_section(&profiler);

        assert!(section.contains("Frame Timings"));
        assert!(section.contains("draw_world"));
        assert!(section.contains("tick_runtime"));
    }

    #[test]
    fn performance_panel_mentions_frame_timings() {
        let mut profiler = ViewerSystemProfilerState::default();
        profiler.record_sample("draw_world", 2.0);

        let panel = format_performance_panel(&profiler);

        assert!(panel.contains("Performance"));
        assert!(panel.contains("Frame Timings"));
        assert!(panel.contains("draw_world"));
    }

    #[test]
    fn selected_tab_uses_distinct_button_color() {
        let selected = hud_tab_button_color(true, Interaction::None).to_srgba();
        let unselected = hud_tab_button_color(false, Interaction::None).to_srgba();

        assert_ne!(selected, unselected);
    }
}
