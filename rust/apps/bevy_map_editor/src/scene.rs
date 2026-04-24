use bevy::prelude::*;
use bevy::render::view::NoIndirectDrawing;
use bevy_egui::input::EguiWantsInput;
use bevy_mesh_outline::OutlineCamera;
use game_bevy::world_render::{
    apply_world_render_camera_projection, build_world_render_scene_from_map_definition,
    build_world_render_scene_from_overworld_definition, spawn_world_render_light_rig,
    spawn_world_render_scene, BuildingWallGridMaterial, GridGroundMaterial, WorldRenderConfig,
    WorldRenderPalette, WorldRenderStyleProfile,
};
use game_data::{
    GridCoord, MapDefinition, MapObjectDefinition, MapObjectKind, OverworldDefinition, OverworldId,
};
use game_editor::load_game_ui_font;

use crate::camera::ray_point_on_horizontal_plane;
use crate::selection::{build_selection_index_from_scene, EditorSelectionIndex};
use crate::state::{
    map_display_name, yes_no, EditorCamera, EditorState, EditorUiState, EditorViewportTarget,
    EditorWorldLabelFont, EditorWorldTileDefinitions, HoveredCellInfo, LibraryView,
    OrbitCameraState, SceneEntity,
};

const HOVERED_GRID_OUTLINE_COLOR: Color = Color::srgba(0.96, 0.97, 0.99, 0.98);
const HOVERED_GRID_OUTLINE_Y_OFFSET: f32 = 0.14;
const HOVERED_GRID_OUTLINE_EXTENT_SCALE: f32 = 0.94;
const EDITOR_GRID_WORLD_SIZE: f32 = 1.0;

pub(crate) fn setup_editor(
    mut commands: Commands,
    mut font_assets: ResMut<Assets<Font>>,
    render_palette: Res<WorldRenderPalette>,
    render_style: Res<WorldRenderStyleProfile>,
    render_config: Res<WorldRenderConfig>,
) {
    let world_label_font = load_game_ui_font(&mut font_assets);
    commands.insert_resource(EditorWorldLabelFont(world_label_font));
    spawn_world_render_light_rig(&mut commands, &render_palette, &render_style);
    let mut perspective = PerspectiveProjection::default();
    apply_world_render_camera_projection(&mut perspective, *render_config);
    commands.spawn((
        Camera3d::default(),
        Msaa::Sample4,
        Projection::from(perspective),
        Transform::from_xyz(18.0, 18.0, 18.0).looking_at(Vec3::ZERO, Vec3::Y),
        EditorCamera,
        OutlineCamera,
        NoIndirectDrawing,
    ));
}

pub(crate) fn rebuild_scene_system(
    mut commands: Commands,
    mut editor: ResMut<EditorState>,
    mut ui_state: ResMut<EditorUiState>,
    mut orbit_camera: ResMut<OrbitCameraState>,
    mut selection_index: ResMut<EditorSelectionIndex>,
    render_config: Res<WorldRenderConfig>,
    render_palette: Res<WorldRenderPalette>,
    asset_server: Res<AssetServer>,
    world_tiles: Res<EditorWorldTileDefinitions>,
    mut images: ResMut<Assets<Image>>,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
    mut ground_materials: ResMut<Assets<GridGroundMaterial>>,
    mut building_wall_materials: ResMut<Assets<BuildingWallGridMaterial>>,
    world_label_font: Res<EditorWorldLabelFont>,
    scene_entities: Query<Entity, (With<SceneEntity>, Without<ChildOf>)>,
) {
    let desired_target = editor.desired_viewport_target();
    if !editor.scene_dirty && desired_target == editor.last_rendered_target {
        return;
    }

    if desired_target != editor.last_rendered_target {
        ui_state.selected_target = None;
    }

    for entity in scene_entities.iter() {
        commands.entity(entity).despawn();
    }

    let Some(desired_target) = desired_target.clone() else {
        editor.status = missing_viewport_target_status(&editor);
        editor.last_rendered_target = None;
        editor.scene_dirty = false;
        editor.scene_revision = editor.scene_revision.saturating_add(1);
        selection_index.clear();
        return;
    };

    match desired_target.clone() {
        EditorViewportTarget::Map { map_id, level } => {
            let Some(document) = editor.maps.get(&map_id).cloned() else {
                editor.status = "Selected tactical map is no longer loaded.".to_string();
                editor.last_rendered_target = None;
                editor.scene_dirty = false;
                editor.scene_revision = editor.scene_revision.saturating_add(1);
                selection_index.clear();
                return;
            };
            orbit_camera.target = map_focus_target(&document.definition);
            let scene = build_world_render_scene_from_map_definition(
                &document.definition,
                level,
                *render_config,
                &world_tiles.0,
            );
            for entity in spawn_world_render_scene(
                &mut commands,
                &asset_server,
                &mut meshes,
                &mut materials,
                &mut ground_materials,
                &mut building_wall_materials,
                &mut images,
                Some(world_label_font.0.clone()),
                &world_tiles.0,
                &scene,
                *render_config,
                &render_palette,
            ) {
                commands.entity(entity).insert(SceneEntity);
            }
            *selection_index = build_selection_index_from_scene(
                &scene,
                &world_tiles.0,
                render_config.floor_thickness_world,
            );
            editor.status = format!(
                "Rendering map {} at level {} in native Bevy 3D.",
                map_display_name(document.definition.id.as_str()),
                level
            );
        }
        EditorViewportTarget::Overworld { overworld_id } => {
            let Some(definition) = editor
                .overworld_library
                .get(&OverworldId(overworld_id))
                .cloned()
            else {
                editor.status = "Selected overworld is no longer loaded.".to_string();
                editor.last_rendered_target = None;
                editor.scene_dirty = false;
                editor.scene_revision = editor.scene_revision.saturating_add(1);
                selection_index.clear();
                return;
            };
            orbit_camera.target = overworld_focus_target(&definition);
            let scene =
                build_world_render_scene_from_overworld_definition(&definition, &world_tiles.0);
            for entity in spawn_world_render_scene(
                &mut commands,
                &asset_server,
                &mut meshes,
                &mut materials,
                &mut ground_materials,
                &mut building_wall_materials,
                &mut images,
                Some(world_label_font.0.clone()),
                &world_tiles.0,
                &scene,
                *render_config,
                &render_palette,
            ) {
                commands.entity(entity).insert(SceneEntity);
            }
            *selection_index = build_selection_index_from_scene(
                &scene,
                &world_tiles.0,
                render_config.floor_thickness_world,
            );
            editor.status = format!(
                "Rendering overworld {} in native Bevy 3D.",
                definition.id.as_str()
            );
        }
    }

    editor.last_rendered_target = Some(desired_target);
    editor.scene_dirty = false;
    editor.scene_revision = editor.scene_revision.saturating_add(1);
}

fn missing_viewport_target_status(editor: &EditorState) -> String {
    match editor.selected_view {
        LibraryView::Maps => {
            if editor.maps.is_empty() {
                "No tactical map available to render.".to_string()
            } else {
                "Selected tactical map is no longer loaded.".to_string()
            }
        }
        LibraryView::Overworlds => {
            if editor.overworld_library.is_empty() {
                "No overworld available to render.".to_string()
            } else {
                "Selected overworld is no longer loaded.".to_string()
            }
        }
    }
}

pub(crate) fn map_focus_target(definition: &MapDefinition) -> Vec3 {
    Vec3::new(
        definition.size.width.saturating_sub(1) as f32 * 0.5,
        0.0,
        definition.size.height.saturating_sub(1) as f32 * 0.5,
    )
}

pub(crate) fn overworld_focus_target(definition: &OverworldDefinition) -> Vec3 {
    Vec3::new(
        definition.size.width.saturating_sub(1) as f32 * 0.5,
        0.0,
        definition.size.height.saturating_sub(1) as f32 * 0.5,
    )
}

pub(crate) fn update_hover_info_system(
    window: Single<&Window>,
    camera_query: Single<(&Camera, &Transform), With<EditorCamera>>,
    egui_wants_input: Res<EguiWantsInput>,
    editor: Res<EditorState>,
    mut ui_state: ResMut<EditorUiState>,
) {
    if egui_wants_input.wants_any_pointer_input() {
        ui_state.hovered_cell = None;
        ui_state.hovered_grid = None;
        return;
    }

    let Some(cursor_position) = window.cursor_position() else {
        ui_state.hovered_cell = None;
        ui_state.hovered_grid = None;
        return;
    };
    if ui_state
        .scene_viewport
        .is_some_and(|viewport| !viewport.contains(cursor_position))
    {
        ui_state.hovered_cell = None;
        ui_state.hovered_grid = None;
        return;
    }

    let (camera, camera_transform) = *camera_query;
    let camera_transform = GlobalTransform::from(*camera_transform);
    let Ok(ray) = camera.viewport_to_world(&camera_transform, cursor_position) else {
        ui_state.hovered_cell = None;
        ui_state.hovered_grid = None;
        return;
    };
    let Some(point) = ray_point_on_horizontal_plane(ray, 0.0) else {
        ui_state.hovered_cell = None;
        ui_state.hovered_grid = None;
        return;
    };

    let hovered = match editor.selected_view {
        LibraryView::Maps => build_map_hover_info(&editor, point),
        LibraryView::Overworlds => build_overworld_hover_info(&editor, point),
    };
    ui_state.hovered_grid = hovered.as_ref().map(|hovered| hovered.grid);
    ui_state.hovered_cell = hovered;
}

pub(crate) fn draw_hovered_grid_outline_system(
    mut gizmos: Gizmos,
    ui_state: Res<EditorUiState>,
    render_config: Res<WorldRenderConfig>,
) {
    let Some(grid) = ui_state.hovered_grid else {
        return;
    };

    draw_grid_outline(
        &mut gizmos,
        grid,
        EDITOR_GRID_WORLD_SIZE,
        render_config
            .floor_thickness_world
            .max(HOVERED_GRID_OUTLINE_Y_OFFSET),
        HOVERED_GRID_OUTLINE_EXTENT_SCALE,
        HOVERED_GRID_OUTLINE_COLOR,
    );
}

fn draw_grid_outline(
    gizmos: &mut Gizmos,
    grid: GridCoord,
    grid_size: f32,
    y_offset: f32,
    extent_scale: f32,
    color: Color,
) {
    let inset = (1.0 - extent_scale).max(0.0) * 0.5 * grid_size;
    let x0 = grid.x as f32 * grid_size + inset;
    let x1 = (grid.x + 1) as f32 * grid_size - inset;
    let z0 = grid.z as f32 * grid_size + inset;
    let z1 = (grid.z + 1) as f32 * grid_size - inset;
    let y = grid.y as f32 * grid_size + y_offset;

    let a = Vec3::new(x0, y, z0);
    let b = Vec3::new(x1, y, z0);
    let c = Vec3::new(x1, y, z1);
    let d = Vec3::new(x0, y, z1);

    gizmos.line(a, b, color);
    gizmos.line(b, c, color);
    gizmos.line(c, d, color);
    gizmos.line(d, a, color);
}

fn build_map_hover_info(editor: &EditorState, point: Vec3) -> Option<HoveredCellInfo> {
    let selected_map_id = editor.selected_map_id.as_ref()?;
    let document = editor.maps.get(selected_map_id)?;
    let grid = GridCoord::new(
        point.x.floor() as i32,
        editor.current_map_level,
        point.z.floor() as i32,
    );

    if grid.x < 0
        || grid.z < 0
        || grid.x >= document.definition.size.width as i32
        || grid.z >= document.definition.size.height as i32
    {
        return None;
    }

    let level = document
        .definition
        .levels
        .iter()
        .find(|level| level.y == editor.current_map_level)?;
    let cell_x = grid.x as u32;
    let cell_z = grid.z as u32;
    let cell = level
        .cells
        .iter()
        .find(|cell| cell.x == cell_x && cell.z == cell_z);
    let objects = document
        .definition
        .objects
        .iter()
        .filter(|object| object_covers_grid(object, grid))
        .collect::<Vec<_>>();

    let mut lines = Vec::new();
    if let Some(cell) = cell {
        lines.push(format!(
            "Cell: terrain={} move_block={} sight_block={}",
            cell.terrain,
            yes_no(cell.blocks_movement),
            yes_no(cell.blocks_sight),
        ));
    } else {
        lines.push("Cell: missing".to_string());
    }

    if objects.is_empty() {
        lines.push("Objects: none".to_string());
    } else {
        lines.push(format!("Objects: {}", objects.len()));
        for object in objects {
            lines.extend(describe_map_object(object));
        }
    }

    Some(HoveredCellInfo {
        grid,
        title: format!("Grid ({}, {}, {})", grid.x, grid.y, grid.z),
        lines,
    })
}

fn build_overworld_hover_info(editor: &EditorState, point: Vec3) -> Option<HoveredCellInfo> {
    let selected_overworld_id = editor.selected_overworld_id.as_ref()?;
    let definition = editor
        .overworld_library
        .get(&OverworldId(selected_overworld_id.clone()))?;
    let grid = GridCoord::new(point.x.floor() as i32, 0, point.z.floor() as i32);
    if grid.x < 0
        || grid.z < 0
        || grid.x >= definition.size.width as i32
        || grid.z >= definition.size.height as i32
    {
        return None;
    }
    let location = definition.locations.iter().find(|location| {
        location.overworld_cell.x == grid.x && location.overworld_cell.z == grid.z
    });
    let cell = definition
        .cells
        .iter()
        .find(|cell| cell.grid.x == grid.x && cell.grid.z == grid.z);

    let mut lines = vec![format!("Overworld: {}", definition.id.as_str())];
    if let Some(cell) = cell {
        lines.push(format!("Terrain: {}", cell.terrain));
        lines.push(format!(
            "Move cost: {}",
            cell.terrain
                .move_cost()
                .map(|cost| cost.to_string())
                .unwrap_or_else(|| "impassable".to_string())
        ));
        lines.push(format!("Blocked: {}", yes_no(cell.blocked)));
        lines.push(format!(
            "Passable: {}",
            yes_no(!cell.blocked && cell.terrain.is_passable())
        ));
    }
    lines.push(format!("Location cell: {}", yes_no(location.is_some())));
    if let Some(location) = location {
        lines.push(format!("Location: {}", location.id.as_str()));
        if !location.name.trim().is_empty() {
            lines.push(format!("Name: {}", location.name));
        }
        lines.push(format!(
            "Kind: {}",
            overworld_location_kind_label(location.kind)
        ));
        lines.push(format!(
            "Map: {}",
            map_display_name(location.map_id.as_str())
        ));
        if !location.entry_point_id.trim().is_empty() {
            lines.push(format!("Entry: {}", location.entry_point_id));
        }
    }

    Some(HoveredCellInfo {
        grid,
        title: format!("Grid ({}, {}, {})", grid.x, grid.y, grid.z),
        lines,
    })
}

fn object_covers_grid(object: &MapObjectDefinition, grid: GridCoord) -> bool {
    if object.anchor.y != grid.y {
        return false;
    }
    let width = object.footprint.width.max(1) as i32;
    let height = object.footprint.height.max(1) as i32;
    grid.x >= object.anchor.x
        && grid.x < object.anchor.x + width
        && grid.z >= object.anchor.z
        && grid.z < object.anchor.z + height
}

fn describe_map_object(object: &MapObjectDefinition) -> Vec<String> {
    let mut lines = vec![format!(
        "- {} [{}] anchor=({}, {}, {}) footprint={}x{}",
        object.object_id,
        map_object_kind_label(object.kind),
        object.anchor.x,
        object.anchor.y,
        object.anchor.z,
        object.footprint.width.max(1),
        object.footprint.height.max(1),
    )];
    lines.push(format!(
        "  blocks: movement={} sight={}",
        yes_no(object.blocks_movement),
        yes_no(object.blocks_sight),
    ));

    match object.kind {
        MapObjectKind::Building => {
            if let Some(building) = &object.props.building {
                if !building.prefab_id.trim().is_empty() {
                    lines.push(format!("  prefab: {}", building.prefab_id));
                }
            }
        }
        MapObjectKind::Prop => {
            if let Some(visual) = &object.props.visual {
                lines.push(format!("  prototype: {}", visual.prototype_id.as_str()));
            }
        }
        MapObjectKind::Pickup => {
            if let Some(pickup) = &object.props.pickup {
                lines.push(format!(
                    "  pickup: item={} count={}..{}",
                    pickup.item_id, pickup.min_count, pickup.max_count
                ));
            }
        }
        MapObjectKind::Interactive => {
            if let Some(interactive) = &object.props.interactive {
                if !interactive.display_name.trim().is_empty() {
                    lines.push(format!("  name: {}", interactive.display_name));
                }
                lines.push(format!("  interaction: {}", interactive.interaction_kind));
                if let Some(target_id) = interactive.target_id.as_deref() {
                    lines.push(format!("  target: {}", target_id));
                }
            }
        }
        MapObjectKind::Trigger => {
            if let Some(trigger) = &object.props.trigger {
                if !trigger.display_name.trim().is_empty() {
                    lines.push(format!("  name: {}", trigger.display_name));
                }
                lines.push(format!("  interaction: {}", trigger.interaction_kind));
                if let Some(target_id) = trigger.target_id.as_deref() {
                    lines.push(format!("  target: {}", target_id));
                }
            }
        }
        MapObjectKind::AiSpawn => {
            if let Some(spawn) = &object.props.ai_spawn {
                lines.push(format!(
                    "  spawn: id={} character={}",
                    spawn.spawn_id, spawn.character_id
                ));
            }
        }
    }

    lines
}

fn map_object_kind_label(kind: MapObjectKind) -> &'static str {
    match kind {
        MapObjectKind::Building => "building",
        MapObjectKind::Prop => "prop",
        MapObjectKind::Pickup => "pickup",
        MapObjectKind::Interactive => "interactive",
        MapObjectKind::Trigger => "trigger",
        MapObjectKind::AiSpawn => "ai_spawn",
    }
}

fn overworld_location_kind_label(kind: game_data::OverworldLocationKind) -> &'static str {
    match kind {
        game_data::OverworldLocationKind::Outdoor => "outdoor",
        game_data::OverworldLocationKind::Interior => "interior",
        game_data::OverworldLocationKind::Dungeon => "dungeon",
    }
}
