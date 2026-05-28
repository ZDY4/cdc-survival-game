//! 游戏内地图面板：用运行时快照绘制当前地图的 2D 俯视图。

use super::map_canvas::spawn_map_canvas;
use super::*;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(in crate::game_ui) struct MapPanelSummary {
    pub visible_buildings: usize,
    pub visible_objects: usize,
    pub visible_actors: usize,
}

pub(super) fn render_map_panel(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    snapshot: &game_core::SimulationSnapshot,
    current_level: i32,
    view_state: &UiMapViewState,
) {
    let body = panel_body(parent, UiMenuPanel::Map);
    parent.commands().entity(body).with_children(|body| {
        if !map_snapshot_is_displayable(snapshot) {
            body.spawn(wrapped_text_bundle(
                font,
                "当前没有可显示的室内/室外地图图像。",
                11.0,
                ui_text_secondary_color(),
            ));
            return;
        }

        let map_name = snapshot
            .grid
            .map_id
            .as_ref()
            .map(|map_id| map_id.as_str())
            .unwrap_or("当前地图");
        body.spawn(text_bundle(
            font,
            &format!("{map_name} · 楼层 {current_level}"),
            11.5,
            ui_text_heading_color(),
        ));

        let summary = map_panel_summary(snapshot, current_level);
        body.spawn(text_bundle(
            font,
            &format!(
                "建筑 {} · 对象 {} · 角色 {}",
                summary.visible_buildings, summary.visible_objects, summary.visible_actors
            ),
            10.0,
            ui_text_muted_color(),
        ));

        if !spawn_map_canvas(body, font, snapshot, current_level, view_state) {
            body.spawn(wrapped_text_bundle(
                font,
                "当前地图尺寸不可用，无法绘制地图图像。",
                11.0,
                ui_text_secondary_color(),
            ));
            return;
        }

        body.spawn(text_bundle(
            font,
            "图例：蓝色=玩家，红色=敌对，绿色=友方，灰色=中立/其他。",
            9.4,
            ui_text_dim_color(),
        ));
    });
}

pub(super) fn map_panel_render_key(
    snapshot: &game_core::SimulationSnapshot,
    current_level: i32,
    view_state: &UiMapViewState,
) -> String {
    let actors = snapshot
        .actors
        .iter()
        .filter(|actor| actor.grid_position.y == current_level)
        .map(|actor| {
            format!(
                "{:?}:{:?}:{}:{}:{}",
                actor.actor_id,
                actor.side,
                actor.display_name,
                actor.grid_position.x,
                actor.grid_position.z
            )
        })
        .collect::<Vec<_>>()
        .join(",");
    let objects = snapshot
        .grid
        .map_objects
        .iter()
        .filter(|object| object_visible_on_level(object, current_level))
        .map(|object| {
            format!(
                "{}:{:?}:{}:{}:{}:{}",
                object.object_id,
                object.kind,
                object.anchor.x,
                object.anchor.z,
                object.occupied_cells.len(),
                object.blocks_movement
            )
        })
        .collect::<Vec<_>>()
        .join(",");
    format!(
        "map={:?}|mode={:?}|level={current_level}|size={:?}x{:?}|topology={}|obstacles={}|zoom={:.3}|pan={:.1},{:.1}|actors={actors}|objects={objects}",
        snapshot.grid.map_id,
        snapshot.interaction_context.world_mode,
        snapshot.grid.map_width,
        snapshot.grid.map_height,
        snapshot.grid.topology_version,
        snapshot.grid.runtime_obstacle_version,
        view_state.zoom,
        view_state.pan.x,
        view_state.pan.y,
    )
}

pub(super) fn map_panel_summary(
    snapshot: &game_core::SimulationSnapshot,
    current_level: i32,
) -> MapPanelSummary {
    let mut visible_buildings = 0;
    let mut visible_objects = 0;
    for object in &snapshot.grid.map_objects {
        if !object_visible_on_level(object, current_level) {
            continue;
        }
        if matches!(object.kind, game_data::MapObjectKind::Building) {
            visible_buildings += 1;
        } else {
            visible_objects += 1;
        }
    }
    let visible_actors = snapshot
        .actors
        .iter()
        .filter(|actor| actor.grid_position.y == current_level)
        .count();
    MapPanelSummary {
        visible_buildings,
        visible_objects,
        visible_actors,
    }
}

fn map_snapshot_is_displayable(snapshot: &game_core::SimulationSnapshot) -> bool {
    !matches!(
        snapshot.interaction_context.world_mode,
        game_data::WorldMode::Overworld
    ) && snapshot.grid.map_id.is_some()
        && snapshot.grid.map_width.unwrap_or(0) > 0
        && snapshot.grid.map_height.unwrap_or(0) > 0
}

pub(super) fn object_visible_on_level(
    object: &game_core::MapObjectDebugState,
    current_level: i32,
) -> bool {
    object.anchor.y == current_level
        || object
            .occupied_cells
            .iter()
            .any(|cell| cell.y == current_level)
}
