//! 地图面板的 2D 画布绘制 helper。

use std::collections::BTreeMap;

use super::map_canvas_geometry::{object_occupied_rects, GridRect};
use super::map_canvas_style::{
    actor_marker_color, object_cell_color, object_outline_color, TerrainVisualKind,
};
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
    body.spawn(map_canvas_viewport_node(layout))
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
        let mut run_start = 0;
        let mut run_style = terrain_style_at(&cells, 0, z);
        for x in 1..=layout.map_width {
            let next_style = (x < layout.map_width).then(|| terrain_style_at(&cells, x, z));
            if next_style != Some(run_style) {
                canvas.spawn(map_terrain_run_node(
                    run_start,
                    z,
                    x - run_start,
                    layout,
                    run_style,
                ));
                run_start = x;
                if let Some(next_style) = next_style {
                    run_style = next_style;
                }
            }
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
        let outline_color = object_outline_color(object);
        for rect in object_occupied_rects(object, current_level) {
            canvas.spawn(map_object_rect_node(rect, layout, color, outline_color));
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

fn map_terrain_run_node(
    x: u32,
    z: u32,
    width_cells: u32,
    layout: MapPanelLayout,
    style: TerrainVisualKind,
) -> impl Bundle {
    (
        Node {
            position_type: PositionType::Absolute,
            left: px(layout.cell_left(x as i32)),
            top: px(layout.cell_top(z as i32)),
            width: px(layout.run_draw_width(width_cells)),
            height: px(layout.terrain_draw_size()),
            ..default()
        },
        BackgroundColor(style.color()),
        viewer_ui_passthrough_bundle(),
    )
}

fn map_object_rect_node(
    rect: GridRect,
    layout: MapPanelLayout,
    color: Color,
    outline_color: Color,
) -> impl Bundle {
    (
        Node {
            position_type: PositionType::Absolute,
            left: px(layout.cell_left(rect.x)),
            top: px(layout.rect_top(rect.z, rect.height)),
            width: px(layout.object_draw_width(rect.width)),
            height: px(layout.object_draw_height(rect.height)),
            border: UiRect::all(px(1)),
            ..default()
        },
        BackgroundColor(color),
        BorderColor::all(outline_color),
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

fn map_canvas_viewport_node(layout: MapPanelLayout) -> impl Bundle {
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
        MapPanelViewport {
            base_content_size: layout.base_content_size,
        },
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

fn terrain_style_at(
    cells: &BTreeMap<(i32, i32), &game_core::MapCellDebugState>,
    x: u32,
    z: u32,
) -> TerrainVisualKind {
    TerrainVisualKind::from_cell(cells.get(&(x as i32, z as i32)).copied())
}

#[derive(Debug, Clone, Copy)]
struct MapPanelLayout {
    map_width: u32,
    map_height: u32,
    cell_size: f32,
    base_content_size: Vec2,
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
        let base_content_size = Vec2::new(
            base_cell_size * map_width as f32,
            base_cell_size * map_height as f32,
        );
        let canvas_width = base_content_size.x * view_state.zoom;
        let canvas_height = base_content_size.y * view_state.zoom;
        Some(Self {
            map_width,
            map_height,
            cell_size,
            base_content_size,
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
        let flipped_z = self.map_height as i32 - z - 1;
        flipped_z.max(0) as f32 * self.cell_size
    }

    fn rect_top(self, z: i32, height: u32) -> f32 {
        let flipped_z = self.map_height as i32 - z - height as i32;
        flipped_z.max(0) as f32 * self.cell_size
    }

    fn terrain_draw_size(self) -> f32 {
        self.cell_size.max(0.75)
    }

    fn run_draw_width(self, cells: u32) -> f32 {
        (self.cell_size * cells as f32 + 0.25).max(0.75)
    }

    fn object_draw_width(self, cells: u32) -> f32 {
        (self.cell_size * cells as f32 - 0.4).max(1.0)
    }

    fn object_draw_height(self, cells: u32) -> f32 {
        (self.cell_size * cells as f32 - 0.4).max(1.0)
    }
}
