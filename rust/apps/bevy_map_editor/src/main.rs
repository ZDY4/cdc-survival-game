use std::path::PathBuf;

use bevy::input::mouse::MouseWheel;
use bevy::prelude::*;
use bevy_egui::input::EguiWantsInput;
use bevy_egui::{egui, EguiContexts, EguiPlugin, EguiPrimaryContextPass};
use game_data::{
    load_map_library, load_overworld_library, MapDefinition, MapId, MapLibrary, MapObjectDefinition,
    MapObjectKind, OverworldDefinition, OverworldId, OverworldLibrary,
};

const TILE_SIZE: f32 = 1.0;
const MAP_TILE_THICKNESS: f32 = 0.08;
const OVERWORLD_TILE_THICKNESS: f32 = 0.06;
const VIEWER_CAMERA_YAW_DEGREES: f32 = 0.0;
const VIEWER_CAMERA_PITCH_DEGREES: f32 = 36.0;
const VIEWER_CAMERA_FOV_DEGREES: f32 = 30.0;
const TEMP_CAMERA_YAW_OFFSET_DEGREES: f32 = 45.0;
const PERSPECTIVE_DISTANCE_DEFAULT: f32 = 28.0;
const TOP_DOWN_DISTANCE_DEFAULT: f32 = 40.0;
const CAMERA_DISTANCE_MIN: f32 = 6.0;
const CAMERA_DISTANCE_MAX: f32 = 160.0;
const MIDDLE_CLICK_TOGGLE_THRESHOLD_PX: f32 = 6.0;

fn main() {
    App::new()
        .add_plugins(
            DefaultPlugins.set(WindowPlugin {
                primary_window: Some(Window {
                    title: "CDC Map Editor".into(),
                    resolution: (1680, 980).into(),
                    ..default()
                }),
                ..default()
            }),
        )
        .add_plugins(EguiPlugin::default())
        .insert_resource(ClearColor(Color::srgb(0.055, 0.06, 0.075)))
        .insert_resource(load_editor_state())
        .insert_resource(OrbitCameraState::default())
        .insert_resource(MiddleClickState::default())
        .add_systems(Startup, setup_editor)
        .add_systems(EguiPrimaryContextPass, editor_ui_system)
        .add_systems(
            Update,
            (
                camera_input_system,
                apply_camera_transform_system,
                rebuild_scene_system,
            ),
        )
        .run();
}

#[derive(Component)]
struct EditorCamera;

#[derive(Component)]
struct SceneEntity;

#[derive(Resource, Debug, Clone)]
struct OrbitCameraState {
    base_yaw: f32,
    base_pitch: f32,
    base_fov: f32,
    yaw_offset: f32,
    is_top_down: bool,
    perspective_distance: f32,
    top_down_distance: f32,
    target: Vec3,
}

impl Default for OrbitCameraState {
    fn default() -> Self {
        Self {
            base_yaw: VIEWER_CAMERA_YAW_DEGREES.to_radians(),
            base_pitch: VIEWER_CAMERA_PITCH_DEGREES.to_radians(),
            base_fov: VIEWER_CAMERA_FOV_DEGREES.to_radians(),
            yaw_offset: 0.0,
            is_top_down: false,
            perspective_distance: PERSPECTIVE_DISTANCE_DEFAULT,
            top_down_distance: TOP_DOWN_DISTANCE_DEFAULT,
            target: Vec3::ZERO,
        }
    }
}

impl OrbitCameraState {
    fn reset_to_default_view(&mut self) {
        self.yaw_offset = 0.0;
        self.is_top_down = false;
        self.perspective_distance = PERSPECTIVE_DISTANCE_DEFAULT;
        self.top_down_distance = TOP_DOWN_DISTANCE_DEFAULT;
    }

    fn active_yaw(&self) -> f32 {
        if self.is_top_down {
            0.0
        } else {
            self.base_yaw + self.yaw_offset
        }
    }

    fn active_pitch(&self) -> f32 {
        if self.is_top_down {
            90.0_f32.to_radians()
        } else {
            self.base_pitch
        }
    }

    fn active_distance(&self) -> f32 {
        if self.is_top_down {
            self.top_down_distance
        } else {
            self.perspective_distance
        }
    }

    fn active_distance_mut(&mut self) -> &mut f32 {
        if self.is_top_down {
            &mut self.top_down_distance
        } else {
            &mut self.perspective_distance
        }
    }
}

#[derive(Resource, Debug, Clone, Default)]
struct MiddleClickState {
    press_position: Option<Vec2>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum LibraryView {
    Maps,
    Overworlds,
}

#[derive(Resource, Debug, Clone)]
struct EditorState {
    map_library: MapLibrary,
    overworld_library: OverworldLibrary,
    selected_view: LibraryView,
    selected_map_id: Option<String>,
    selected_overworld_id: Option<String>,
    current_map_level: i32,
    search_text: String,
    status: String,
    scene_dirty: bool,
    scene_revision: u64,
}

fn load_editor_state() -> EditorState {
    let map_path = project_data_dir("maps");
    let overworld_path = project_data_dir("overworld");

    let map_result = load_map_library(&map_path);
    let overworld_result = load_overworld_library(&overworld_path);
    let map_error = map_result.as_ref().err().map(|error| error.to_string());
    let overworld_error = overworld_result.as_ref().err().map(|error| error.to_string());

    match (&map_result, &overworld_result) {
        (Ok(map_library), Ok(overworld_library)) => {
            let selected_map_id = map_library.iter().next().map(|(id, _)| id.as_str().to_string());
            let selected_overworld_id = overworld_library
                .iter()
                .next()
                .map(|(id, _)| id.as_str().to_string());
            let current_map_level = selected_map_id
                .as_ref()
                .and_then(|id| map_library.get(&MapId(id.clone())))
                .map(|definition| definition.default_level)
                .unwrap_or(0);

            EditorState {
                status: format!(
                    "Loaded {} tactical maps and {} overworld documents.",
                    map_library.len(),
                    overworld_library.len()
                ),
                map_library: map_library.clone(),
                overworld_library: overworld_library.clone(),
                selected_view: LibraryView::Maps,
                selected_map_id,
                selected_overworld_id,
                current_map_level,
                search_text: String::new(),
                scene_dirty: true,
                scene_revision: 0,
            }
        }
        _ => EditorState {
            map_library: map_result.unwrap_or_default(),
            overworld_library: overworld_result.unwrap_or_default(),
            selected_view: LibraryView::Maps,
            selected_map_id: None,
            selected_overworld_id: None,
            current_map_level: 0,
            search_text: String::new(),
            status: format!(
                "Failed to load project content. maps={}; overworld={}",
                map_error.unwrap_or_else(|| "ok".to_string()),
                overworld_error.unwrap_or_else(|| "ok".to_string())
            ),
            scene_dirty: true,
            scene_revision: 0,
        },
    }
}

fn project_data_dir(kind: &str) -> PathBuf {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../..");
    root.join("data").join(kind)
}

fn setup_editor(mut commands: Commands) {
    commands.insert_resource(GlobalAmbientLight {
        color: Color::WHITE,
        brightness: 350.0,
        affects_lightmapped_meshes: true,
    });

    commands.spawn((
        Camera3d::default(),
        Msaa::Sample4,
        Projection::from(PerspectiveProjection {
            fov: VIEWER_CAMERA_FOV_DEGREES.to_radians(),
            near: 0.1,
            far: 2000.0,
            ..PerspectiveProjection::default()
        }),
        Transform::from_xyz(18.0, 18.0, 18.0).looking_at(Vec3::ZERO, Vec3::Y),
        EditorCamera,
    ));

    commands.spawn((
        DirectionalLight {
            shadows_enabled: true,
            illuminance: 32_000.0,
            ..default()
        },
        Transform::from_xyz(14.0, 22.0, 10.0).looking_at(Vec3::ZERO, Vec3::Y),
    ));
}

fn editor_ui_system(
    mut contexts: EguiContexts,
    mut editor: ResMut<EditorState>,
    mut orbit_camera: ResMut<OrbitCameraState>,
) {
    let ctx = contexts
        .ctx_mut()
        .expect("primary egui context should exist for the map editor");

    egui::TopBottomPanel::top("map_editor_top_bar").show(ctx, |ui| {
        ui.horizontal(|ui| {
            ui.heading("CDC Map Editor");
            ui.separator();
            ui.label("Maps has moved out of Tauri. This window is now the native Bevy host.");
            if ui.button("Reset Camera").clicked() {
                orbit_camera.reset_to_default_view();
                editor.status = "Camera reset to bevy_debug_viewer default angle.".to_string();
            }
            ui.separator();
            ui.label(if orbit_camera.is_top_down {
                "View: Top Down"
            } else {
                "View: Perspective"
            });
        });
    });

    egui::TopBottomPanel::bottom("map_editor_status_bar").show(ctx, |ui| {
        ui.horizontal_wrapped(|ui| {
            ui.label(&editor.status);
            ui.separator();
            ui.label(format!("Scene revision {}", editor.scene_revision));
            if editor.selected_view == LibraryView::Maps {
                ui.separator();
                ui.label(format!("Current level {}", editor.current_map_level));
            }
        });
    });

    egui::SidePanel::left("map_editor_library")
        .resizable(true)
        .default_width(320.0)
        .show(ctx, |ui| {
            let previous_view = editor.selected_view;
            ui.heading("Library");
            ui.horizontal(|ui| {
                ui.selectable_value(&mut editor.selected_view, LibraryView::Maps, "Maps");
                ui.selectable_value(&mut editor.selected_view, LibraryView::Overworlds, "Overworlds");
            });
            if editor.selected_view != previous_view {
                editor.scene_dirty = true;
            }
            ui.add_space(8.0);
            ui.label("Search");
            ui.text_edit_singleline(&mut editor.search_text);
            ui.add_space(8.0);

            match editor.selected_view {
                LibraryView::Maps => {
                    draw_map_library(ui, &mut editor, &mut orbit_camera);
                }
                LibraryView::Overworlds => {
                    draw_overworld_library(ui, &mut editor, &mut orbit_camera);
                }
            }
        });

    egui::SidePanel::right("map_editor_inspector")
        .resizable(true)
        .default_width(320.0)
        .show(ctx, |ui| match editor.selected_view {
            LibraryView::Maps => draw_map_inspector(ui, &mut editor),
            LibraryView::Overworlds => draw_overworld_inspector(ui, &editor),
        });
}

fn draw_map_library(ui: &mut egui::Ui, editor: &mut EditorState, orbit_camera: &mut OrbitCameraState) {
    let query = editor.search_text.trim().to_lowercase();

    egui::ScrollArea::vertical().show(ui, |ui| {
        for (map_id, definition) in editor.map_library.iter() {
            let matches_query = query.is_empty()
                || map_id.as_str().to_lowercase().contains(&query)
                || definition.name.to_lowercase().contains(&query);
            if !matches_query {
                continue;
            }

            let is_selected = editor.selected_map_id.as_deref() == Some(map_id.as_str());
            let response = ui.selectable_label(
                is_selected,
                format!(
                    "{}{}",
                    map_id.as_str(),
                    if definition.name.is_empty() {
                        String::new()
                    } else {
                        format!(" · {}", definition.name)
                    }
                ),
            );

            if response.clicked() {
                editor.selected_map_id = Some(map_id.as_str().to_string());
                editor.current_map_level = definition.default_level;
                editor.scene_dirty = true;
                editor.status = format!("Selected tactical map {}.", map_id.as_str());
                orbit_camera.target = map_focus_target(definition);
            }
        }
    });
}

fn draw_overworld_library(
    ui: &mut egui::Ui,
    editor: &mut EditorState,
    orbit_camera: &mut OrbitCameraState,
) {
    let query = editor.search_text.trim().to_lowercase();

    egui::ScrollArea::vertical().show(ui, |ui| {
        for (overworld_id, definition) in editor.overworld_library.iter() {
            let matches_query =
                query.is_empty() || overworld_id.as_str().to_lowercase().contains(&query);
            if !matches_query {
                continue;
            }

            let is_selected = editor.selected_overworld_id.as_deref() == Some(overworld_id.as_str());
            let response = ui.selectable_label(
                is_selected,
                format!(
                    "{} · {} locations",
                    overworld_id.as_str(),
                    definition.locations.len()
                ),
            );

            if response.clicked() {
                editor.selected_overworld_id = Some(overworld_id.as_str().to_string());
                editor.scene_dirty = true;
                editor.status = format!("Selected overworld {}.", overworld_id.as_str());
                orbit_camera.target = overworld_focus_target(definition);
            }
        }
    });
}

fn draw_map_inspector(ui: &mut egui::Ui, editor: &mut EditorState) {
    ui.heading("Map Inspector");

    let Some(selected_map_id) = editor.selected_map_id.as_ref() else {
        ui.label("No tactical map selected.");
        return;
    };

    let Some(definition) = editor.map_library.get(&MapId(selected_map_id.clone())) else {
        ui.label("Selected tactical map no longer exists.");
        return;
    };

    ui.label(format!("Id: {}", definition.id.as_str()));
    if !definition.name.is_empty() {
        ui.label(format!("Name: {}", definition.name));
    }
    ui.label(format!(
        "Size: {} x {} · levels: {} · objects: {}",
        definition.size.width,
        definition.size.height,
        definition.levels.len(),
        definition.objects.len()
    ));

    let levels: Vec<i32> = definition.levels.iter().map(|level| level.y).collect();
    ui.add_space(8.0);
    ui.horizontal(|ui| {
        if ui.button("Level -").clicked() {
            if let Some(next_level) = levels
                .iter()
                .copied()
                .filter(|level| *level < editor.current_map_level)
                .max()
            {
                editor.current_map_level = next_level;
                editor.scene_dirty = true;
                editor.status = format!(
                    "Viewing map {} on level {}.",
                    definition.id.as_str(),
                    editor.current_map_level
                );
            }
        }
        ui.label(format!("Current level {}", editor.current_map_level));
        if ui.button("Level +").clicked() {
            if let Some(next_level) = levels
                .iter()
                .copied()
                .filter(|level| *level > editor.current_map_level)
                .min()
            {
                editor.current_map_level = next_level;
                editor.scene_dirty = true;
                editor.status = format!(
                    "Viewing map {} on level {}.",
                    definition.id.as_str(),
                    editor.current_map_level
                );
            }
        }
    });

    ui.add_space(8.0);
    ui.collapsing("Objects", |ui| {
        if definition.objects.is_empty() {
            ui.label("No placed objects.");
            return;
        }

        egui::ScrollArea::vertical().max_height(320.0).show(ui, |ui| {
            for object in definition
                .objects
                .iter()
                .filter(|object| object.anchor.y == editor.current_map_level)
            {
                ui.label(format!(
                    "{} · {:?} @ ({}, {}, {})",
                    object.object_id, object.kind, object.anchor.x, object.anchor.y, object.anchor.z
                ));
            }
        });
    });

    ui.add_space(8.0);
    ui.small("This first Bevy host focuses on native library browsing and 3D scene inspection. Tauri no longer owns maps.");
}

fn draw_overworld_inspector(ui: &mut egui::Ui, editor: &EditorState) {
    ui.heading("Overworld Inspector");

    let Some(selected_overworld_id) = editor.selected_overworld_id.as_ref() else {
        ui.label("No overworld selected.");
        return;
    };

    let Some(definition) = editor
        .overworld_library
        .get(&OverworldId(selected_overworld_id.clone()))
    else {
        ui.label("Selected overworld no longer exists.");
        return;
    };

    ui.label(format!("Id: {}", definition.id.as_str()));
    ui.label(format!(
        "Locations: {} · walkable cells: {}",
        definition.locations.len(),
        definition.walkable_cells.len()
    ));
    ui.add_space(8.0);
    ui.small("Overworlds are now hosted here too. 3D scene scaffolding is active, but authoring tools are still minimal.");
}

fn camera_input_system(
    time: Res<Time>,
    window: Single<&Window>,
    keys: Res<ButtonInput<KeyCode>>,
    buttons: Res<ButtonInput<MouseButton>>,
    mut wheel_events: MessageReader<MouseWheel>,
    mut orbit_camera: ResMut<OrbitCameraState>,
    mut middle_click_state: ResMut<MiddleClickState>,
    egui_wants_input: Res<EguiWantsInput>,
    mut editor: ResMut<EditorState>,
) {
    let wants_keyboard_input = egui_wants_input.wants_any_keyboard_input();
    let wants_pointer_input = egui_wants_input.wants_any_pointer_input();

    if wants_keyboard_input {
        orbit_camera.yaw_offset = 0.0;
    } else if orbit_camera.is_top_down {
        orbit_camera.yaw_offset = 0.0;
    } else if keys.pressed(KeyCode::KeyQ) && !keys.pressed(KeyCode::KeyE) {
        orbit_camera.yaw_offset = -TEMP_CAMERA_YAW_OFFSET_DEGREES.to_radians();
    } else if keys.pressed(KeyCode::KeyE) && !keys.pressed(KeyCode::KeyQ) {
        orbit_camera.yaw_offset = TEMP_CAMERA_YAW_OFFSET_DEGREES.to_radians();
    } else {
        orbit_camera.yaw_offset = 0.0;
    }

    if !wants_keyboard_input {
        let movement = gather_keyboard_movement(&keys);
        if movement != Vec2::ZERO {
            let move_speed = camera_pan_speed(orbit_camera.active_distance()) * time.delta_secs();
            let world_delta = camera_pan_delta(&orbit_camera, movement.normalize(), move_speed);
            orbit_camera.target += world_delta;
        }
    }

    if wants_pointer_input {
        for _ in wheel_events.read() {}
        if buttons.just_pressed(MouseButton::Middle) {
            middle_click_state.press_position = None;
        }
    } else {
        for event in wheel_events.read() {
            let unit_scale = match event.unit {
                bevy::input::mouse::MouseScrollUnit::Line => 1.0,
                bevy::input::mouse::MouseScrollUnit::Pixel => 0.1,
            };
            let next_distance = (*orbit_camera.active_distance_mut() - event.y * unit_scale * 1.8)
                .clamp(CAMERA_DISTANCE_MIN, CAMERA_DISTANCE_MAX);
            *orbit_camera.active_distance_mut() = next_distance;
        }
    }

    if buttons.just_pressed(MouseButton::Middle) {
        middle_click_state.press_position = if wants_pointer_input {
            None
        } else {
            window.cursor_position()
        };
    }

    if buttons.just_released(MouseButton::Middle) {
        let toggled = middle_click_state
            .press_position
            .zip(window.cursor_position())
            .map(|(start, end)| start.distance(end) <= MIDDLE_CLICK_TOGGLE_THRESHOLD_PX)
            .unwrap_or(false);

        if toggled && !wants_pointer_input {
            orbit_camera.is_top_down = !orbit_camera.is_top_down;
            orbit_camera.yaw_offset = 0.0;
            editor.status = if orbit_camera.is_top_down {
                "Camera switched to top-down view.".to_string()
            } else {
                "Camera restored to perspective view.".to_string()
            };
        }
        middle_click_state.press_position = None;
    }
}

fn apply_camera_transform_system(
    orbit_camera: Res<OrbitCameraState>,
    mut cameras: Query<(&mut Projection, &mut Transform), With<EditorCamera>>,
) {
    let Ok((mut projection, mut transform)) = cameras.single_mut() else {
        return;
    };

    if let Projection::Perspective(perspective) = &mut *projection {
        perspective.fov = orbit_camera.base_fov;
        perspective.near = 0.1;
        perspective.far = 2000.0;
    }

    let pitch = orbit_camera.active_pitch();
    let yaw = orbit_camera.active_yaw();
    let distance = orbit_camera.active_distance();
    let horizontal = distance * pitch.cos();
    let eye = orbit_camera.target
        + Vec3::new(
            horizontal * yaw.sin(),
            distance * pitch.sin(),
            -horizontal * yaw.cos(),
        );

    transform.translation = eye;
    transform.look_at(
        orbit_camera.target,
        if orbit_camera.is_top_down {
            Vec3::Z
        } else {
            Vec3::Y
        },
    );
}

fn rebuild_scene_system(
    mut commands: Commands,
    mut editor: ResMut<EditorState>,
    mut orbit_camera: ResMut<OrbitCameraState>,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
    scene_entities: Query<Entity, With<SceneEntity>>,
) {
    if !editor.scene_dirty {
        return;
    }

    for entity in scene_entities.iter() {
        commands.entity(entity).despawn();
    }

    match editor.selected_view {
        LibraryView::Maps => {
            let Some(selected_map_id) = editor.selected_map_id.as_ref() else {
                editor.status = "No tactical map available to render.".to_string();
                editor.scene_dirty = false;
                return;
            };

            let Some(definition) = editor.map_library.get(&MapId(selected_map_id.clone())).cloned() else {
                editor.status = format!("Map {} no longer exists.", selected_map_id);
                editor.scene_dirty = false;
                return;
            };

            orbit_camera.target = map_focus_target(&definition);
            spawn_map_scene(&mut commands, &mut meshes, &mut materials, &definition, editor.current_map_level);
            editor.status = format!(
                "Rendering map {} at level {} in native Bevy 3D.",
                definition.id.as_str(),
                editor.current_map_level
            );
        }
        LibraryView::Overworlds => {
            let Some(selected_overworld_id) = editor.selected_overworld_id.as_ref() else {
                editor.status = "No overworld available to render.".to_string();
                editor.scene_dirty = false;
                return;
            };

            let Some(definition) = editor
                .overworld_library
                .get(&OverworldId(selected_overworld_id.clone()))
                .cloned()
            else {
                editor.status = format!("Overworld {} no longer exists.", selected_overworld_id);
                editor.scene_dirty = false;
                return;
            };

            orbit_camera.target = overworld_focus_target(&definition);
            spawn_overworld_scene(&mut commands, &mut meshes, &mut materials, &definition);
            editor.status = format!(
                "Rendering overworld {} in native Bevy 3D.",
                definition.id.as_str()
            );
        }
    }

    editor.scene_dirty = false;
    editor.scene_revision = editor.scene_revision.saturating_add(1);
}

fn spawn_map_scene(
    commands: &mut Commands,
    meshes: &mut Assets<Mesh>,
    materials: &mut Assets<StandardMaterial>,
    definition: &MapDefinition,
    current_level: i32,
) {
    let floor_open_material = materials.add(StandardMaterial {
        base_color: Color::srgb(0.18, 0.22, 0.27),
        perceptual_roughness: 0.94,
        ..default()
    });
    let floor_blocked_material = materials.add(StandardMaterial {
        base_color: Color::srgb(0.42, 0.20, 0.18),
        perceptual_roughness: 0.88,
        ..default()
    });
    let floor_missing_material = materials.add(StandardMaterial {
        base_color: Color::srgba(0.12, 0.14, 0.18, 0.55),
        alpha_mode: AlphaMode::Blend,
        ..default()
    });

    let Some(level) = definition.levels.iter().find(|level| level.y == current_level) else {
        return;
    };

    for x in 0..definition.size.width {
        for z in 0..definition.size.height {
            let cell = level.cells.iter().find(|cell| cell.x == x && cell.z == z);
            let material = match cell {
                Some(cell) if cell.blocks_movement || cell.blocks_sight => floor_blocked_material.clone(),
                Some(_) => floor_open_material.clone(),
                None => floor_missing_material.clone(),
            };

            commands.spawn((
                Mesh3d(meshes.add(Cuboid::new(TILE_SIZE * 0.94, MAP_TILE_THICKNESS, TILE_SIZE * 0.94))),
                MeshMaterial3d(material),
                Transform::from_xyz(x as f32, MAP_TILE_THICKNESS * 0.5, z as f32),
                SceneEntity,
                Name::new(format!("cell-{x}-{z}")),
            ));
        }
    }

    for object in definition
        .objects
        .iter()
        .filter(|object| object.anchor.y == current_level)
    {
        spawn_map_object(commands, meshes, materials, object);
    }
}

fn spawn_map_object(
    commands: &mut Commands,
    meshes: &mut Assets<Mesh>,
    materials: &mut Assets<StandardMaterial>,
    object: &MapObjectDefinition,
) {
    let (color, height) = match object.kind {
        MapObjectKind::Building => (Color::srgb(0.70, 0.72, 0.78), 1.8),
        MapObjectKind::Pickup => (Color::srgb(0.92, 0.72, 0.18), 0.45),
        MapObjectKind::Interactive => (Color::srgb(0.24, 0.72, 0.84), 0.95),
        MapObjectKind::Trigger => (Color::srgb(0.88, 0.35, 0.58), 0.22),
        MapObjectKind::AiSpawn => (Color::srgb(0.50, 0.40, 0.86), 1.15),
    };

    let width = object.footprint.width.max(1) as f32 * 0.88;
    let depth = object.footprint.height.max(1) as f32 * 0.88;
    let center_x = object.anchor.x as f32 + object.footprint.width.max(1) as f32 * 0.5 - 0.5;
    let center_z = object.anchor.z as f32 + object.footprint.height.max(1) as f32 * 0.5 - 0.5;

    commands.spawn((
        Mesh3d(meshes.add(Cuboid::new(width, height, depth))),
        MeshMaterial3d(materials.add(StandardMaterial {
            base_color: color,
            perceptual_roughness: 0.72,
            ..default()
        })),
        Transform::from_xyz(center_x, MAP_TILE_THICKNESS + height * 0.5, center_z),
        SceneEntity,
        Name::new(format!("object-{}", object.object_id)),
    ));
}

fn spawn_overworld_scene(
    commands: &mut Commands,
    meshes: &mut Assets<Mesh>,
    materials: &mut Assets<StandardMaterial>,
    definition: &OverworldDefinition,
) {
    let walkable_material = materials.add(StandardMaterial {
        base_color: Color::srgb(0.18, 0.42, 0.28),
        perceptual_roughness: 0.9,
        ..default()
    });
    let location_material = materials.add(StandardMaterial {
        base_color: Color::srgb(0.22, 0.58, 0.86),
        perceptual_roughness: 0.65,
        ..default()
    });

    for cell in &definition.walkable_cells {
        commands.spawn((
            Mesh3d(meshes.add(Cuboid::new(TILE_SIZE * 0.82, OVERWORLD_TILE_THICKNESS, TILE_SIZE * 0.82))),
            MeshMaterial3d(walkable_material.clone()),
            Transform::from_xyz(cell.grid.x as f32, OVERWORLD_TILE_THICKNESS * 0.5, cell.grid.z as f32),
            SceneEntity,
            Name::new(format!("overworld-cell-{}-{}", cell.grid.x, cell.grid.z)),
        ));
    }

    for location in &definition.locations {
        commands.spawn((
            Mesh3d(meshes.add(Cuboid::new(0.72, 1.4, 0.72))),
            MeshMaterial3d(location_material.clone()),
            Transform::from_xyz(location.overworld_cell.x as f32, 0.75, location.overworld_cell.z as f32),
            SceneEntity,
            Name::new(format!("location-{}", location.id.as_str())),
        ));
    }
}

fn map_focus_target(definition: &MapDefinition) -> Vec3 {
    Vec3::new(
        definition.size.width.saturating_sub(1) as f32 * 0.5,
        0.0,
        definition.size.height.saturating_sub(1) as f32 * 0.5,
    )
}

fn overworld_focus_target(definition: &OverworldDefinition) -> Vec3 {
    if let Some(first_location) = definition.locations.first() {
        Vec3::new(
            first_location.overworld_cell.x as f32,
            0.0,
            first_location.overworld_cell.z as f32,
        )
    } else {
        Vec3::ZERO
    }
}

fn gather_keyboard_movement(keys: &ButtonInput<KeyCode>) -> Vec2 {
    let mut movement = Vec2::ZERO;

    if keys.pressed(KeyCode::KeyW) {
        movement.y += 1.0;
    }
    if keys.pressed(KeyCode::KeyS) {
        movement.y -= 1.0;
    }
    if keys.pressed(KeyCode::KeyD) {
        movement.x += 1.0;
    }
    if keys.pressed(KeyCode::KeyA) {
        movement.x -= 1.0;
    }

    movement
}

fn camera_pan_speed(distance: f32) -> f32 {
    (distance * 0.45).clamp(4.0, 28.0)
}

fn camera_pan_delta(orbit_camera: &OrbitCameraState, movement: Vec2, move_speed: f32) -> Vec3 {
    if orbit_camera.is_top_down {
        return Vec3::new(movement.x, 0.0, movement.y) * move_speed;
    }

    let yaw = orbit_camera.active_yaw();
    let forward = Vec3::new(yaw.sin(), 0.0, yaw.cos());
    let right = Vec3::new(forward.z, 0.0, -forward.x);
    (forward * movement.y + right * movement.x) * move_speed
}
