use bevy::prelude::*;
use game_core::{ActorDebugState, SimulationSnapshot};
use game_data::{GridCoord, InteractionPrompt};

use crate::dialogue::current_dialogue_node;
use crate::geometry::{
    actor_label, camera_world_distance, focused_target_summary, format_optional_grid, grid_bounds,
    map_object_at_grid, movement_block_reasons, rendered_path_preview, selected_actor,
    sight_block_reasons, visible_world_footprint,
};
use crate::state::{
    HudEventCategory, HudEventFilter, HudFooterText, HudText, ViewerEventEntry, ViewerHudPage,
    ViewerRenderConfig, ViewerRuntimeState, ViewerState,
};

pub(crate) fn update_hud(
    window: Single<&Window>,
    hud_text: Single<(&mut Text, &mut Visibility), With<HudText>>,
    mut hud_footer: Single<&mut TextSpan, With<HudFooterText>>,
    runtime_state: Res<ViewerRuntimeState>,
    viewer_state: Res<ViewerState>,
    render_config: Res<ViewerRenderConfig>,
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
    let summary = format_status_summary(
        &window,
        &snapshot,
        &runtime_state,
        &viewer_state,
        *render_config,
    );
    let page_body = match viewer_state.hud_page {
        ViewerHudPage::Overview => format_overview_panel(
            &window,
            &snapshot,
            &runtime_state,
            &viewer_state,
            *render_config,
        ),
        ViewerHudPage::SelectedActor => {
            format_selected_actor_panel(&snapshot, &runtime_state, &viewer_state)
        }
        ViewerHudPage::World => format_world_panel(&snapshot, &runtime_state, &viewer_state),
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
        "{} {:?} {:?} group={} ap={:.1} steps={} grid=({}, {}, {})",
        actor_label(actor),
        actor.actor_id,
        actor.side,
        actor.group_id,
        actor.ap,
        actor.available_steps,
        actor.grid_position.x,
        actor.grid_position.y,
        actor.grid_position.z
    )
}

fn format_status_summary(
    window: &Window,
    snapshot: &SimulationSnapshot,
    runtime_state: &ViewerRuntimeState,
    viewer_state: &ViewerState,
    render_config: ViewerRenderConfig,
) -> String {
    let selected = selected_actor(snapshot, viewer_state)
        .map(actor_overview_summary)
        .unwrap_or_else(|| "none".to_string());
    let pending_path = rendered_path_preview(
        &runtime_state.runtime,
        snapshot,
        runtime_state.runtime.pending_movement(),
    );
    let view = camera_view_summary(window, snapshot, viewer_state, render_config);

    [
        format!(
            "status={} | auto_tick={} | zoom={}",
            if viewer_state.status_line.is_empty() {
                "idle"
            } else {
                viewer_state.status_line.as_str()
            },
            viewer_state.auto_tick,
            view
        ),
        format!(
            "combat={} actor={:?} group={:?} turn={} | pending={:?} move={} path={}",
            snapshot.combat.in_combat,
            snapshot.combat.current_actor_id,
            snapshot.combat.current_group_id,
            snapshot.combat.current_turn_index,
            runtime_state.runtime.peek_pending_progression(),
            runtime_state.runtime.pending_movement().is_some(),
            pending_path.len()
        ),
        format!(
            "map={} level={} mode={:?} | selected={} | target={}",
            snapshot
                .grid
                .map_id
                .as_ref()
                .map(|map_id| map_id.as_str())
                .unwrap_or("none"),
            viewer_state.current_level,
            snapshot.interaction_context.world_mode,
            selected,
            focused_target_summary(snapshot, viewer_state)
        ),
    ]
    .join("\n")
}

fn format_overview_panel(
    window: &Window,
    snapshot: &SimulationSnapshot,
    runtime_state: &ViewerRuntimeState,
    viewer_state: &ViewerState,
    render_config: ViewerRenderConfig,
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
                format!(
                    "map={} size={}x{} level={} default={} levels={:?}",
                    snapshot
                        .grid
                        .map_id
                        .as_ref()
                        .map(|map_id| map_id.as_str())
                        .unwrap_or("none"),
                    snapshot.grid.map_width.unwrap_or(0),
                    snapshot.grid.map_height.unwrap_or(0),
                    viewer_state.current_level,
                    snapshot.grid.default_level.unwrap_or(0),
                    snapshot.grid.levels
                ),
                format!(
                    "combat={} current_actor={:?} current_group={:?} turn_index={}",
                    snapshot.combat.in_combat,
                    snapshot.combat.current_actor_id,
                    snapshot.combat.current_group_id,
                    snapshot.combat.current_turn_index
                ),
                format!(
                    "world_mode={:?} outdoor={:?} subscene={:?}",
                    snapshot.interaction_context.world_mode,
                    snapshot.interaction_context.active_outdoor_location_id,
                    snapshot.interaction_context.current_subscene_location_id
                ),
            ],
        ),
        section("Selected", vec![format!("actor={selected}")]),
        section(
            "Focus",
            vec![format!(
                "target={}",
                focused_target_summary(snapshot, viewer_state)
            )],
        ),
        section(
            "Runtime",
            vec![
                format!(
                    "pending_progression={:?} pending_movement={}",
                    runtime_state.runtime.peek_pending_progression(),
                    runtime_state.runtime.pending_movement().is_some()
                ),
                format!(
                    "path_preview={} hovered_grid={}",
                    rendered_path_preview(
                        &runtime_state.runtime,
                        snapshot,
                        runtime_state.runtime.pending_movement(),
                    )
                    .len(),
                    format_optional_grid(viewer_state.hovered_grid)
                ),
                format!(
                    "zoom={} auto_tick={}",
                    camera_view_summary(window, snapshot, viewer_state, render_config),
                    viewer_state.auto_tick
                ),
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

    let world = runtime_state.runtime.grid_to_world(actor.grid_position);
    let mut lines = vec![
        format!("name={} id={:?}", actor_label(actor), actor.actor_id),
        format!(
            "definition={} kind={:?} side={:?} group={}",
            actor
                .definition_id
                .as_ref()
                .map(|id| id.as_str())
                .unwrap_or("none"),
            actor.kind,
            actor.side,
            actor.group_id
        ),
        format!(
            "grid=({}, {}, {}) world=({:.1}, {:.1}, {:.1})",
            actor.grid_position.x,
            actor.grid_position.y,
            actor.grid_position.z,
            world.x,
            world.y,
            world.z
        ),
        format!(
            "ap={:.1} steps={} turn_open={} in_combat={} current_turn={}",
            actor.ap,
            actor.available_steps,
            actor.turn_open,
            actor.in_combat,
            snapshot.combat.current_actor_id == Some(actor.actor_id)
        ),
        format!(
            "focused_target={}",
            focused_target_summary(snapshot, viewer_state)
        ),
    ];

    if let Some(intent) = runtime_state.runtime.pending_movement() {
        let pending_path = rendered_path_preview(
            &runtime_state.runtime,
            snapshot,
            runtime_state.runtime.pending_movement(),
        );
        lines.push(format!(
            "pending_move actor_match={} goal=({}, {}, {}) path_cells={}",
            intent.actor_id == actor.actor_id,
            intent.requested_goal.x,
            intent.requested_goal.y,
            intent.requested_goal.z,
            pending_path.len()
        ));
    } else {
        lines.push("pending_move=none".to_string());
    }

    if let Some(hover_grid) = viewer_state.hovered_grid {
        let dx = (actor.grid_position.x - hover_grid.x).abs();
        let dy = (actor.grid_position.y - hover_grid.y).abs();
        let dz = (actor.grid_position.z - hover_grid.z).abs();
        lines.push(format!(
            "distance_to_hover manhattan={} chebyshev={} hover=({}, {}, {})",
            dx + dy + dz,
            dx.max(dy).max(dz),
            hover_grid.x,
            hover_grid.y,
            hover_grid.z
        ));
    } else {
        lines.push("distance_to_hover=none".to_string());
    }

    section("Selected Actor", lines)
}

fn format_world_panel(
    snapshot: &SimulationSnapshot,
    runtime_state: &ViewerRuntimeState,
    viewer_state: &ViewerState,
) -> String {
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
                format!(
                    "map={} grid_size={:.2} size={}x{} current_level={} default={} levels={:?}",
                    snapshot
                        .grid
                        .map_id
                        .as_ref()
                        .map(|map_id| map_id.as_str())
                        .unwrap_or("none"),
                    snapshot.grid.grid_size,
                    snapshot.grid.map_width.unwrap_or(0),
                    snapshot.grid.map_height.unwrap_or(0),
                    level,
                    snapshot.grid.default_level.unwrap_or(0),
                    snapshot.grid.levels
                ),
                format!(
                    "topology_version={} runtime_obstacle_version={}",
                    snapshot.grid.topology_version, snapshot.grid.runtime_obstacle_version
                ),
                format!(
                    "actors={} objects={} static_obstacles={} runtime_blocked={}",
                    actor_count, object_count, static_obstacle_count, runtime_blocked_count
                ),
            ],
        ),
        format_hover_section(snapshot, runtime_state, viewer_state),
    ];

    if let Some(grid) = viewer_state.hovered_grid {
        if let Some(object) = map_object_at_grid(snapshot, grid) {
            sections.push(section(
                "Hovered Object",
                vec![
                    format!(
                        "id={} kind={:?} anchor=({}, {}, {}) rotation={:?}",
                        object.object_id,
                        object.kind,
                        object.anchor.x,
                        object.anchor.y,
                        object.anchor.z,
                        object.rotation
                    ),
                    format!(
                        "footprint={:?} occupied={}",
                        object.footprint,
                        format_grid_list(&object.occupied_cells)
                    ),
                    format!(
                        "blocks_movement={} blocks_sight={}",
                        object.blocks_movement, object.blocks_sight
                    ),
                    format!(
                        "payload={}",
                        format_payload_summary(&object.payload_summary)
                    ),
                ],
            ));
        }
    }

    sections.join("\n\n")
}

fn format_hover_section(
    snapshot: &SimulationSnapshot,
    runtime_state: &ViewerRuntimeState,
    viewer_state: &ViewerState,
) -> String {
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
    let world = runtime_state.runtime.grid_to_world(grid);
    let movement_reasons = movement_block_reasons(snapshot, grid);
    let sight_reasons = sight_block_reasons(snapshot, grid);

    section(
        "Hover Cell",
        vec![
            format!(
                "grid=({}, {}, {}) world=({:.1}, {:.1}, {:.1})",
                grid.x, grid.y, grid.z, world.x, world.y, world.z
            ),
            format!(
                "terrain={} blocks_movement={} blocks_sight={}",
                cell.map(|entry| entry.terrain.as_str()).unwrap_or("none"),
                cell.map(|entry| entry.blocks_movement).unwrap_or(false),
                cell.map(|entry| entry.blocks_sight).unwrap_or(false)
            ),
            format!(
                "map_blocked={} runtime_blocked={}",
                snapshot.grid.map_blocked_cells.contains(&grid),
                snapshot.grid.runtime_blocked_cells.contains(&grid)
            ),
            format!(
                "movement={}",
                if movement_reasons.is_empty() {
                    "walkable".to_string()
                } else {
                    format!("blocked_by {}", movement_reasons.join(", "))
                }
            ),
            format!(
                "sight={}",
                if sight_reasons.is_empty() {
                    "clear".to_string()
                } else {
                    format!("blocked_by {}", sight_reasons.join(", "))
                }
            ),
            format!("actors={}", format_string_list(&actors)),
            format!("objects={}", format_string_list(&objects)),
        ],
    )
}

fn format_interaction_panel(snapshot: &SimulationSnapshot, viewer_state: &ViewerState) -> String {
    let mut sections = vec![
        section(
            "Focused Target",
            vec![format!(
                "target={}",
                focused_target_summary(snapshot, viewer_state)
            )],
        ),
        format_prompt_section(viewer_state.current_prompt.as_ref()),
        format_dialogue_section(viewer_state.active_dialogue.as_ref()),
        section(
            "Interaction Context",
            vec![
                format!(
                    "mode={:?} map={}",
                    snapshot.interaction_context.world_mode,
                    snapshot
                        .interaction_context
                        .current_map_id
                        .as_deref()
                        .unwrap_or("none")
                ),
                format!(
                    "outdoor={:?} subscene={:?}",
                    snapshot.interaction_context.active_outdoor_location_id,
                    snapshot.interaction_context.current_subscene_location_id
                ),
                format!(
                    "return_spawn={:?}",
                    snapshot.interaction_context.return_outdoor_spawn_id
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
        format!(
            "actor={:?} target={:?} target_name={}",
            prompt.actor_id, prompt.target_id, prompt.target_name
        ),
        format!(
            "anchor=({}, {}, {}) primary_option={}",
            prompt.anchor_grid.x,
            prompt.anchor_grid.y,
            prompt.anchor_grid.z,
            prompt
                .primary_option_id
                .as_ref()
                .map(|id| id.0.as_str())
                .unwrap_or("none")
        ),
    ];

    if prompt.options.is_empty() {
        lines.push("options=none".to_string());
    } else {
        lines.extend(prompt.options.iter().enumerate().map(|(index, option)| {
            format!(
                "{}. {} kind={:?} danger={} prox={} dist={:.1} pri={}{}",
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
        format!(
            "dialog_id={} target={} node_id={} type={}",
            dialogue.dialog_id, dialogue.target_name, node.id, node.node_type
        ),
        format!(
            "speaker={}",
            if node.speaker.trim().is_empty() {
                "none"
            } else {
                node.speaker.as_str()
            }
        ),
        format!("text={}", compact_text(&node.text)),
    ];

    if node.options.is_empty() {
        lines.push("choices=none".to_string());
    } else {
        lines.push(format!("choices={}", node.options.len()));
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
    let total_count = runtime_state.recent_events.len();
    let combat_count = runtime_state
        .recent_events
        .iter()
        .filter(|entry| entry.category == HudEventCategory::Combat)
        .count();
    let interaction_count = runtime_state
        .recent_events
        .iter()
        .filter(|entry| entry.category == HudEventCategory::Interaction)
        .count();
    let world_count = runtime_state
        .recent_events
        .iter()
        .filter(|entry| entry.category == HudEventCategory::World)
        .count();
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
            vec![
                format!("filter={} empty", event_filter.label()),
                format!(
                    "counts total={} combat={} interaction={} world={}",
                    total_count, combat_count, interaction_count, world_count
                ),
            ]
        } else {
            std::iter::once(format!(
                "filter={} visible={} total={} combat={} interaction={} world={}",
                event_filter.label(),
                events.len(),
                total_count,
                combat_count,
                interaction_count,
                world_count
            ))
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

    let mut lines = vec![format!("entries={}", snapshot.entries.len())];
    for entry in snapshot.entries.iter().take(6) {
        let top_scores = entry
            .goal_scores
            .iter()
            .take(3)
            .map(|score| format!("{:?}:{}", score.goal, score.score))
            .collect::<Vec<_>>()
            .join(", ");
        lines.push(format!(
            "entity={:?} mode={:?} actor={:?} role={:?} goal={:?} action={:?}/{:?}",
            entry.entity,
            entry.execution_mode,
            entry.runtime_actor_id,
            entry.role,
            entry.goal,
            entry.action,
            entry.action_phase,
        ));
        lines.push(format!(
            "anchor={:?} goal_grid={:?} reservations={:?} failure={:?}",
            entry.current_anchor,
            entry.runtime_goal_grid,
            entry.reservations,
            entry.last_failure_reason
        ));
        lines.push(format!(
            "needs(h/e/m)={}/{}/{} on_shift={} meal_window_open={} plan={}/{}",
            entry.need_hunger,
            entry.need_energy,
            entry.need_morale,
            entry.on_shift,
            entry.meal_window_open,
            entry.plan_next_index,
            entry.plan_total_steps
        ));
        lines.push(format!("top_scores=[{}]", top_scores));
        lines.push(format!("summary={}", entry.decision_summary));
    }

    section("AI", lines)
}

fn format_controls_help() -> String {
    section(
        "Controls",
        vec![
            "F1-F6 switch HUD page".to_string(),
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

fn camera_view_summary(
    window: &Window,
    snapshot: &SimulationSnapshot,
    viewer_state: &ViewerState,
    render_config: ViewerRenderConfig,
) -> String {
    let bounds = grid_bounds(snapshot, viewer_state.current_level);
    let camera_distance = camera_world_distance(
        bounds,
        window.width(),
        window.height(),
        snapshot.grid.grid_size,
        render_config,
    );
    let footprint = visible_world_footprint(
        window.width(),
        window.height(),
        camera_distance,
        render_config,
    );
    format!(
        "{:.0}% | fov={:.0}deg | view={:.1}x{:.1}wu",
        render_config.zoom_factor * 100.0,
        render_config.camera_fov_degrees,
        footprint.x,
        footprint.y
    )
}

pub(crate) fn footer_hint(page: ViewerHudPage) -> &'static str {
    match page {
        ViewerHudPage::Overview => {
            "F1-6切页 · H隐藏HUD · /帮助 · A自动推进 · PgUp/Dn楼层 · Tab切换角色"
        }
        ViewerHudPage::SelectedActor => {
            "F1-6切页 · H隐藏HUD · /帮助 · Tab切换角色 · 左键选中/交互/移动 · 右键打开交互菜单"
        }
        ViewerHudPage::World => {
            "F1-6切页 · H隐藏HUD · /帮助 · 悬停看格子 · 中键拖拽 · 滚轮缩放 · F回中"
        }
        ViewerHudPage::Interaction => {
            "F1-6切页 · H隐藏HUD · /帮助 · 左键主交互 · 右键开菜单 · 点击按钮执行交互 · 1-9选对话分支"
        }
        ViewerHudPage::Events => "F1-6切页 · H隐藏HUD · /帮助 · [ / ]切过滤器",
        ViewerHudPage::Ai => "F1-6切页 · H隐藏HUD · /帮助 · 查看 AI 目标 / 动作 / 预订 / 班次",
    }
}

fn section(title: &str, lines: Vec<String>) -> String {
    let mut text = String::from(title);
    for line in lines {
        text.push_str("\n- ");
        text.push_str(&line);
    }
    text
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

fn format_grid_list(values: &[GridCoord]) -> String {
    if values.is_empty() {
        "none".to_string()
    } else {
        values
            .iter()
            .map(|grid| format!("({}, {}, {})", grid.x, grid.y, grid.z))
            .collect::<Vec<_>>()
            .join(", ")
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
