//! 地图面板的 2D 画布绘制 helper。

use std::collections::BTreeMap;

use super::*;

const MAP_CANVAS_MAX_WIDTH: f32 = MAP_PANEL_WIDTH - 40.0;
const MAP_CANVAS_MAX_HEIGHT: f32 = 430.0;
const MAP_CELL_MAX_SIZE: f32 = 22.0;
const MAP_CELL_MIN_SIZE: f32 = 2.0;
const MAP_ACTOR_MARKER_SIZE: f32 = 10.0;

pub(super) fn spawn_map_canvas(
    body: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    snapshot: &game_core::SimulationSnapshot,
    current_level: i32,
    view_state: &UiMapViewState,
) -> bool {
    let Some(layout) = MapPanelLayout::from_snapshot(snapshot, view_state) else {
        return false;
    };
    body.spawn(map_canvas_viewport_node())
        .with_children(|viewport| {
            viewport
                .spawn(map_canvas_content_node(layout))
                .with_children(|canvas| {
                    spawn_terrain_cells(canvas, snapshot, current_level, layout);
                    spawn_map_objects(canvas, snapshot, current_level, layout);
                    spawn_actor_markers(canvas, font, snapshot, current_level, layout);
                });
        });
    true
}

fn spawn_terrain_cells(
    canvas: &mut ChildSpawnerCommands,
    snapshot: &game_core::SimulationSnapshot,
    current_level: i32,
    layout: MapPanelLayout,
) {
    let cells = snapshot
        .grid
        .map_cells
        .iter()
        .filter(|cell| cell.grid.y == current_level)
        .map(|cell| ((cell.grid.x, cell.grid.z), cell))
        .collect::<BTreeMap<_, _>>();

    for z in 0..layout.map_height {
        for x in 0..layout.map_width {
            let cell = cells.get(&(x as i32, z as i32)).copied();
            canvas.spawn(map_cell_node(
                x,
                z,
                layout,
                cell.map(terrain_cell_color)
                    .unwrap_or_else(unknown_cell_color),
                cell.is_some_and(|cell| cell.blocks_movement),
            ));
        }
    }
}

fn spawn_map_objects(
    canvas: &mut ChildSpawnerCommands,
    snapshot: &game_core::SimulationSnapshot,
    current_level: i32,
    layout: MapPanelLayout,
) {
    for object in snapshot
        .grid
        .map_objects
        .iter()
        .filter(|object| super::map::object_visible_on_level(object, current_level))
    {
        let color = object_cell_color(object);
        for cell in object
            .occupied_cells
            .iter()
            .copied()
            .filter(|cell| cell.y == current_level)
        {
            canvas.spawn(map_cell_overlay_node(cell.x, cell.z, layout, color));
        }
    }
}

fn spawn_actor_markers(
    canvas: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    snapshot: &game_core::SimulationSnapshot,
    current_level: i32,
    layout: MapPanelLayout,
) {
    for actor in snapshot
        .actors
        .iter()
        .filter(|actor| actor.grid_position.y == current_level)
    {
        let x = layout.cell_left(actor.grid_position.x) + layout.cell_size * 0.5
            - MAP_ACTOR_MARKER_SIZE * 0.5;
        let top = layout.cell_top(actor.grid_position.z) + layout.cell_size * 0.5
            - MAP_ACTOR_MARKER_SIZE * 0.5;
        canvas
            .spawn(actor_marker_node(x, top, actor_marker_color(actor.side)))
            .with_children(|marker| {
                marker.spawn((
                    Node {
                        position_type: PositionType::Absolute,
                        left: px(MAP_ACTOR_MARKER_SIZE + 3.0),
                        top: px(-3.0),
                        ..default()
                    },
                    Text::new(actor.display_name.clone()),
                    TextFont::from_font_size(8.0).with_font(font.0.clone()),
                    TextColor(Color::WHITE),
                    TextLayout::new(Justify::Left, LineBreak::NoWrap),
                    viewer_ui_passthrough_bundle(),
                ));
            });
    }
}

fn map_cell_node(
    x: u32,
    z: u32,
    layout: MapPanelLayout,
    color: Color,
    blocked: bool,
) -> impl Bundle {
    (
        Node {
            position_type: PositionType::Absolute,
            left: px(layout.cell_left(x as i32)),
            top: px(layout.cell_top(z as i32)),
            width: px(layout.cell_draw_size()),
            height: px(layout.cell_draw_size()),
            border: UiRect::all(px(if blocked { 1.0 } else { 0.0 })),
            ..default()
        },
        BackgroundColor(color),
        BorderColor::all(Color::srgba(0.15, 0.14, 0.12, 0.7)),
        viewer_ui_passthrough_bundle(),
    )
}

fn map_cell_overlay_node(x: i32, z: i32, layout: MapPanelLayout, color: Color) -> impl Bundle {
    (
        Node {
            position_type: PositionType::Absolute,
            left: px(layout.cell_left(x)),
            top: px(layout.cell_top(z)),
            width: px(layout.cell_draw_size()),
            height: px(layout.cell_draw_size()),
            border: UiRect::all(px(1)),
            ..default()
        },
        BackgroundColor(color),
        BorderColor::all(Color::srgba(0.02, 0.02, 0.018, 0.82)),
        viewer_ui_passthrough_bundle(),
    )
}

fn actor_marker_node(left: f32, top: f32, color: Color) -> impl Bundle {
    (
        Node {
            position_type: PositionType::Absolute,
            left: px(left),
            top: px(top),
            width: px(MAP_ACTOR_MARKER_SIZE),
            height: px(MAP_ACTOR_MARKER_SIZE),
            border: UiRect::all(px(1)),
            ..default()
        },
        BackgroundColor(color),
        BorderColor::all(Color::WHITE),
        viewer_ui_passthrough_bundle(),
    )
}

fn map_canvas_viewport_node() -> impl Bundle {
    (
        Node {
            width: px(MAP_CANVAS_MAX_WIDTH),
            height: px(MAP_CANVAS_MAX_HEIGHT),
            align_self: AlignSelf::Center,
            position_type: PositionType::Relative,
            overflow: Overflow::clip(),
            border: UiRect::all(px(1)),
            ..default()
        },
        BackgroundColor(Color::srgba(0.025, 0.026, 0.024, 0.98)),
        BorderColor::all(ui_border_strong_color()),
        RelativeCursorPosition::default(),
        MapPanelViewport,
        UiMouseBlocker,
        UiMouseBlockerName("地图画布".to_string()),
        viewer_ui_passthrough_bundle(),
    )
}

fn map_canvas_content_node(layout: MapPanelLayout) -> impl Bundle {
    (
        Node {
            position_type: PositionType::Absolute,
            left: px(layout.content_left),
            top: px(layout.content_top),
            width: px(layout.canvas_width),
            height: px(layout.canvas_height),
            ..default()
        },
        viewer_ui_passthrough_bundle(),
    )
}

fn terrain_cell_color(cell: &game_core::MapCellDebugState) -> Color {
    let terrain = cell.terrain.as_str();
    if cell.blocks_movement {
        return Color::srgba(0.12, 0.115, 0.105, 1.0);
    }
    match terrain {
        "road" | "asphalt" | "concrete" => Color::srgba(0.23, 0.235, 0.23, 1.0),
        "grass" | "plain" | "field" => Color::srgba(0.16, 0.24, 0.15, 1.0),
        "forest" => Color::srgba(0.10, 0.19, 0.12, 1.0),
        "water" => Color::srgba(0.08, 0.19, 0.28, 1.0),
        "urban" => Color::srgba(0.20, 0.20, 0.19, 1.0),
        _ => Color::srgba(0.18, 0.18, 0.165, 1.0),
    }
}

fn unknown_cell_color() -> Color {
    Color::srgba(0.065, 0.065, 0.06, 1.0)
}

fn object_cell_color(object: &game_core::MapObjectDebugState) -> Color {
    match object.kind {
        game_data::MapObjectKind::Building => Color::srgba(0.47, 0.42, 0.34, 0.95),
        game_data::MapObjectKind::Trigger => Color::srgba(0.70, 0.56, 0.18, 0.42),
        game_data::MapObjectKind::Interactive => Color::srgba(0.36, 0.46, 0.56, 0.55),
        game_data::MapObjectKind::AiSpawn => Color::srgba(0.48, 0.28, 0.58, 0.45),
        game_data::MapObjectKind::Pickup => Color::srgba(0.56, 0.44, 0.25, 0.45),
        game_data::MapObjectKind::Prop => Color::srgba(0.28, 0.27, 0.25, 0.55),
    }
}

fn actor_marker_color(side: game_data::ActorSide) -> Color {
    match side {
        game_data::ActorSide::Player => Color::srgba(0.24, 0.56, 0.95, 1.0),
        game_data::ActorSide::Friendly => Color::srgba(0.24, 0.68, 0.34, 1.0),
        game_data::ActorSide::Hostile => Color::srgba(0.90, 0.24, 0.20, 1.0),
        game_data::ActorSide::Neutral => Color::srgba(0.74, 0.72, 0.66, 1.0),
    }
}

#[derive(Debug, Clone, Copy)]
struct MapPanelLayout {
    map_width: u32,
    map_height: u32,
    cell_size: f32,
    canvas_width: f32,
    canvas_height: f32,
    content_left: f32,
    content_top: f32,
}

impl MapPanelLayout {
    fn from_snapshot(
        snapshot: &game_core::SimulationSnapshot,
        view_state: &UiMapViewState,
    ) -> Option<Self> {
        let map_width = snapshot.grid.map_width?;
        let map_height = snapshot.grid.map_height?;
        if map_width == 0 || map_height == 0 {
            return None;
        }
        let raw_cell_size = (MAP_CANVAS_MAX_WIDTH / map_width as f32)
            .min(MAP_CANVAS_MAX_HEIGHT / map_height as f32)
            .min(MAP_CELL_MAX_SIZE);
        let base_cell_size = if raw_cell_size < MAP_CELL_MIN_SIZE {
            raw_cell_size.max(0.75)
        } else {
            raw_cell_size
        };
        let cell_size = base_cell_size
            * view_state
                .zoom
                .clamp(UiMapViewState::MIN_ZOOM, UiMapViewState::MAX_ZOOM);
        let canvas_width = cell_size * map_width as f32;
        let canvas_height = cell_size * map_height as f32;
        Some(Self {
            map_width,
            map_height,
            cell_size,
            canvas_width,
            canvas_height,
            content_left: (MAP_CANVAS_MAX_WIDTH - canvas_width) * 0.5 + view_state.pan.x,
            content_top: (MAP_CANVAS_MAX_HEIGHT - canvas_height) * 0.5 + view_state.pan.y,
        })
    }

    fn cell_left(self, x: i32) -> f32 {
        x.max(0) as f32 * self.cell_size
    }

    fn cell_top(self, z: i32) -> f32 {
        z.max(0) as f32 * self.cell_size
    }

    fn cell_draw_size(self) -> f32 {
        (self.cell_size - 1.0).max(0.75)
    }
}
