use std::fs;
use std::path::{Path, PathBuf};

use bevy::asset::LoadState;
use bevy::camera::primitives::MeshAabb;
use bevy::camera::{CameraOutputMode, ClearColorConfig};
use bevy::log::{info, warn, LogPlugin};
use bevy::prelude::*;
use bevy::render::render_resource::BlendState;
use bevy_egui::{
    egui, EguiContexts, EguiGlobalSettings, EguiPlugin, EguiPrimaryContextPass, PrimaryEguiContext,
};
use game_bevy::{init_runtime_logging, rust_asset_dir, RuntimeLogSettings};
use game_editor::{
    apply_preview_orbit_camera, build_persisted_primary_window, install_game_ui_fonts,
    preview_camera_input_system as shared_preview_camera_input_system,
    preview_camera_sync_system as shared_preview_camera_sync_system, replace_preview_scene,
    spawn_preview_floor, spawn_preview_light_rig, spawn_preview_scene_host,
    PreviewCameraController, PreviewFloor, PreviewOrbitCamera, PreviewViewportRect,
    WindowSizePersistenceConfig, WindowSizePersistencePlugin,
};

const PREVIEW_BG: Color = Color::srgb(0.095, 0.105, 0.125);
const MODEL_PANEL_WIDTH: f32 = 320.0;
const CAMERA_RADIUS_MIN: f32 = 0.8;
const CAMERA_RADIUS_MAX: f32 = 18.0;
const DEFAULT_MODEL_VIEWPORT_FILL: f32 = 0.5;

fn main() {
    let window_config =
        WindowSizePersistenceConfig::new("bevy_gltf_viewer", 1600.0, 920.0, 1280.0, 720.0);
    let log_settings = RuntimeLogSettings::new("bevy_gltf_viewer").with_single_run_file();
    if let Err(error) = init_runtime_logging(&log_settings) {
        eprintln!("failed to initialize bevy_gltf_viewer logging: {error}");
    } else {
        info!("bevy_gltf_viewer logger initialized");
    }
    App::new()
        .add_plugins(
            DefaultPlugins
                .build()
                .disable::<LogPlugin>()
                .set(WindowPlugin {
                    primary_window: Some(build_persisted_primary_window(
                        window_config.clone(),
                        "CDC glTF Viewer",
                    )),
                    ..default()
                })
                .set(AssetPlugin {
                    file_path: gltf_viewer_asset_dir().display().to_string(),
                    ..default()
                }),
        )
        .add_plugins(EguiPlugin::default())
        .add_plugins(WindowSizePersistencePlugin::new(window_config))
        .insert_resource(ClearColor(PREVIEW_BG))
        .insert_resource(ModelCatalog::scan(&gltf_viewer_asset_dir()))
        .insert_resource(ViewerUiState::default())
        .insert_resource(PreviewState::default())
        .insert_resource(ViewerEguiFontState::default())
        .add_systems(Startup, setup_viewer)
        .add_systems(
            EguiPrimaryContextPass,
            (configure_egui_fonts_system, viewer_ui_system).chain(),
        )
        .add_systems(
            Update,
            (
                shared_preview_camera_input_system,
                sync_preview_scene_system,
                refresh_preview_load_status_system,
                frame_loaded_scene_system,
                sync_preview_ground_visibility_system,
                shared_preview_camera_sync_system,
            )
                .chain(),
        )
        .run();
}

fn gltf_viewer_asset_dir() -> PathBuf {
    rust_asset_dir()
}

fn default_viewer_orbit() -> PreviewOrbitCamera {
    PreviewOrbitCamera {
        focus: Vec3::ZERO,
        yaw_radians: -0.55,
        pitch_radians: -0.12,
        radius: 4.4,
    }
}

#[derive(Debug, Clone, Copy)]
struct SceneWorldBounds {
    min: Vec3,
    max: Vec3,
}

impl SceneWorldBounds {
    fn from_point(point: Vec3) -> Self {
        Self {
            min: point,
            max: point,
        }
    }

    fn include_point(&mut self, point: Vec3) {
        self.min = self.min.min(point);
        self.max = self.max.max(point);
    }

    fn center(self) -> Vec3 {
        (self.min + self.max) * 0.5
    }

    fn size(self) -> Vec3 {
        self.max - self.min
    }
}

#[derive(Debug, Clone)]
struct ModelEntry {
    display_name: String,
    relative_path: String,
    search_text: String,
}

impl ModelEntry {
    fn new(relative_path: String) -> Self {
        let display_name = Path::new(&relative_path)
            .file_name()
            .and_then(|value| value.to_str())
            .unwrap_or(relative_path.as_str())
            .to_string();
        Self {
            display_name,
            search_text: relative_path.to_ascii_lowercase(),
            relative_path,
        }
    }
}

#[derive(Resource, Debug, Clone)]
struct ModelCatalog {
    asset_root: PathBuf,
    entries: Vec<ModelEntry>,
}

impl ModelCatalog {
    fn scan(asset_root: &Path) -> Self {
        let mut entries = Vec::new();
        collect_models(asset_root, asset_root, &mut entries);
        entries.sort_by(|left, right| left.relative_path.cmp(&right.relative_path));
        Self {
            asset_root: asset_root.to_path_buf(),
            entries,
        }
    }
}

#[derive(Resource, Debug, Clone)]
struct ViewerUiState {
    search_text: String,
    selected_model_path: Option<String>,
    show_ground: bool,
}

impl Default for ViewerUiState {
    fn default() -> Self {
        Self {
            search_text: String::new(),
            selected_model_path: None,
            show_ground: false,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
enum PreviewLoadStatus {
    Idle,
    Loading,
    Ready,
    Failed(String),
}

impl Default for PreviewLoadStatus {
    fn default() -> Self {
        Self::Idle
    }
}

impl PreviewLoadStatus {
    fn label(&self) -> String {
        match self {
            Self::Idle => "未选择模型".to_string(),
            Self::Loading => "加载中…".to_string(),
            Self::Ready => "已加载".to_string(),
            Self::Failed(error) => format!("加载失败: {error}"),
        }
    }
}

#[derive(Resource, Debug, Default)]
struct PreviewState {
    host_entity: Option<Entity>,
    scene_instance: Option<Entity>,
    scene_handle: Option<Handle<Scene>>,
    requested_model_path: Option<String>,
    applied_model_path: Option<String>,
    framed_model_path: Option<String>,
    load_status: PreviewLoadStatus,
}

#[derive(Resource, Debug, Clone, Default)]
struct ViewerEguiFontState {
    initialized: bool,
}

#[derive(Component)]
struct PreviewCamera;

fn setup_viewer(
    mut commands: Commands,
    mut egui_global_settings: ResMut<EguiGlobalSettings>,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
    catalog: Res<ModelCatalog>,
    mut ui_state: ResMut<ViewerUiState>,
    mut preview_state: ResMut<PreviewState>,
) {
    egui_global_settings.auto_create_primary_context = false;
    info!(
        "gltf viewer catalog loaded: {} model(s)",
        catalog.entries.len()
    );

    ui_state.selected_model_path = catalog
        .entries
        .first()
        .map(|entry| entry.relative_path.clone());
    preview_state.requested_model_path = ui_state.selected_model_path.clone();
    preview_state.host_entity = Some(spawn_preview_scene_host(&mut commands));

    spawn_preview_light_rig(&mut commands);
    spawn_preview_floor(
        &mut commands,
        &mut meshes,
        &mut materials,
        Vec2::new(8.0, 8.0),
        Color::srgb(0.22, 0.235, 0.26),
    );
    commands.spawn((
        Camera3d::default(),
        Camera {
            order: 0,
            clear_color: ClearColorConfig::Custom(PREVIEW_BG),
            ..default()
        },
        Projection::Perspective(PerspectiveProjection {
            fov: std::f32::consts::FRAC_PI_4,
            near: 0.01,
            far: 200.0,
            ..default()
        }),
        Transform::from_xyz(2.8, 1.8, 4.0).looking_at(Vec3::new(0.0, 0.7, 0.0), Vec3::Y),
        PreviewCameraController {
            orbit: default_viewer_orbit(),
            focus_anchor: default_viewer_orbit().focus,
            viewport_rect: None,
            rotate_drag_active: false,
            pan_drag_active: false,
            allow_rotate: true,
            allow_pan: true,
            allow_zoom: true,
            pitch_min: -1.2,
            pitch_max: 0.72,
            radius_min: CAMERA_RADIUS_MIN,
            radius_max: CAMERA_RADIUS_MAX,
            rotate_speed_x: 0.012,
            rotate_speed_y: 0.008,
            zoom_speed: 0.24,
            pan_speed: 1.0,
            pan_max_focus_offset: 2.8,
        },
        PreviewCamera,
    ));
    commands.spawn((
        PrimaryEguiContext,
        Camera2d,
        Camera {
            order: 1,
            output_mode: CameraOutputMode::Write {
                blend_state: Some(BlendState::ALPHA_BLENDING),
                clear_color: ClearColorConfig::None,
            },
            clear_color: ClearColorConfig::Custom(Color::NONE),
            ..default()
        },
    ));
}

fn configure_egui_fonts_system(
    mut contexts: EguiContexts,
    mut font_state: ResMut<ViewerEguiFontState>,
) {
    if font_state.initialized {
        return;
    }
    let Ok(ctx) = contexts.ctx_mut() else {
        return;
    };

    install_game_ui_fonts(ctx);

    let mut style = (*ctx.style()).clone();
    style.spacing.item_spacing = egui::vec2(6.0, 4.0);
    style.spacing.button_padding = egui::vec2(8.0, 5.0);
    style.visuals.widgets.noninteractive.corner_radius = 4.0.into();
    style.visuals.widgets.inactive.corner_radius = 4.0.into();
    style.visuals.widgets.hovered.corner_radius = 4.0.into();
    style.visuals.widgets.active.corner_radius = 4.0.into();
    ctx.set_style(style);

    font_state.initialized = true;
}

fn viewer_ui_system(
    mut contexts: EguiContexts,
    catalog: Res<ModelCatalog>,
    mut ui_state: ResMut<ViewerUiState>,
    mut preview_state: ResMut<PreviewState>,
    mut preview_camera: Single<&mut PreviewCameraController, With<PreviewCamera>>,
) {
    let Ok(ctx) = contexts.ctx_mut() else {
        return;
    };

    egui::SidePanel::left("model_list")
        .resizable(false)
        .exact_width(MODEL_PANEL_WIDTH)
        .show(ctx, |ui| {
            ui.heading("模型列表");
            ui.label(format!("资产根: {}", catalog.asset_root.display()));
            ui.add_space(8.0);
            ui.label("搜索");
            ui.text_edit_singleline(&mut ui_state.search_text);
            ui.checkbox(&mut ui_state.show_ground, "显示地面");
            ui.add_space(8.0);

            let query = ui_state.search_text.trim().to_ascii_lowercase();
            let filtered = catalog
                .entries
                .iter()
                .filter(|entry| query.is_empty() || entry.search_text.contains(&query))
                .collect::<Vec<_>>();

            ui.small(format!(
                "{} / {} 个模型",
                filtered.len(),
                catalog.entries.len()
            ));
            ui.separator();

            egui::ScrollArea::vertical().show(ui, |ui| {
                for entry in filtered {
                    let selected = ui_state.selected_model_path.as_deref()
                        == Some(entry.relative_path.as_str());
                    let response = ui
                        .add_sized(
                            [ui.available_width(), 0.0],
                            egui::Button::new(entry.display_name.as_str())
                                .selected(selected)
                                .truncate(),
                        )
                        .on_hover_text(entry.relative_path.as_str());
                    if response.clicked() {
                        ui_state.selected_model_path = Some(entry.relative_path.clone());
                        preview_camera.set_orbit(default_viewer_orbit());
                    }
                }
            });
        });

    egui::CentralPanel::default()
        .frame(egui::Frame::NONE)
        .show(ctx, |ui| {
            let rect = ui.max_rect();
            preview_camera.viewport_rect = Some(PreviewViewportRect {
                min_x: rect.min.x,
                min_y: rect.min.y,
                width: rect.width(),
                height: rect.height(),
            });
            ui.allocate_rect(rect, egui::Sense::hover());
            let info_rect = egui::Rect::from_min_size(
                rect.left_top() + egui::vec2(10.0, 10.0),
                egui::vec2(360.0, 56.0),
            );
            ui.painter().rect_filled(
                info_rect,
                6.0,
                egui::Color32::from_rgba_unmultiplied(18, 21, 28, 176),
            );
            ui.painter().text(
                rect.left_top() + egui::vec2(14.0, 12.0),
                egui::Align2::LEFT_TOP,
                "glTF 预览",
                egui::FontId::new(14.0, egui::FontFamily::Proportional),
                egui::Color32::from_rgb(228, 231, 238),
            );
            ui.painter().text(
                rect.left_top() + egui::vec2(14.0, 32.0),
                egui::Align2::LEFT_TOP,
                ui_state
                    .selected_model_path
                    .as_deref()
                    .unwrap_or("未找到可预览的 glTF/glb"),
                egui::FontId::new(11.0, egui::FontFamily::Proportional),
                egui::Color32::from_rgb(164, 170, 184),
            );
            ui.painter().text(
                rect.left_top() + egui::vec2(14.0, 50.0),
                egui::Align2::LEFT_TOP,
                preview_state.load_status.label(),
                egui::FontId::new(11.0, egui::FontFamily::Proportional),
                egui::Color32::from_rgb(164, 170, 184),
            );
            paint_axis_gizmo(ui, rect, preview_camera.orbit);
        });

    if preview_state.requested_model_path != ui_state.selected_model_path {
        preview_state.requested_model_path = ui_state.selected_model_path.clone();
    }
}

fn sync_preview_scene_system(
    mut commands: Commands,
    asset_server: Res<AssetServer>,
    mut preview_state: ResMut<PreviewState>,
) {
    if preview_state.requested_model_path == preview_state.applied_model_path {
        return;
    }

    let Some(host_entity) = preview_state.host_entity else {
        return;
    };

    let Some(path) = preview_state.requested_model_path.clone() else {
        if let Some(instance) = preview_state.scene_instance.take() {
            commands.entity(instance).despawn();
        }
        preview_state.scene_handle = None;
        preview_state.applied_model_path = None;
        preview_state.framed_model_path = None;
        preview_state.load_status = PreviewLoadStatus::Idle;
        return;
    };

    info!("gltf viewer selected model: {path}");
    let (_, handle) = replace_preview_scene(
        &mut commands,
        &asset_server,
        host_entity,
        &mut preview_state.scene_instance,
        path.clone(),
    );
    preview_state.scene_handle = Some(handle);
    preview_state.applied_model_path = Some(path);
    preview_state.framed_model_path = None;
    preview_state.load_status = PreviewLoadStatus::Loading;
}

fn refresh_preview_load_status_system(
    asset_server: Res<AssetServer>,
    mut preview_state: ResMut<PreviewState>,
) {
    let Some(handle) = preview_state.scene_handle.as_ref() else {
        return;
    };
    let Some(load_state) = asset_server.get_load_state(handle) else {
        return;
    };

    match load_state {
        LoadState::Failed(error) => {
            warn!("gltf viewer failed to load model: {}", error);
            preview_state.load_status = PreviewLoadStatus::Failed(error.to_string());
        }
        LoadState::Loaded => {
            if asset_server
                .recursive_dependency_load_state(handle)
                .is_loaded()
            {
                preview_state.load_status = PreviewLoadStatus::Ready;
            } else {
                preview_state.load_status = PreviewLoadStatus::Loading;
            }
        }
        _ => {
            preview_state.load_status = PreviewLoadStatus::Loading;
        }
    }
}

fn frame_loaded_scene_system(
    mut preview_state: ResMut<PreviewState>,
    mut preview_camera: Single<&mut PreviewCameraController, With<PreviewCamera>>,
    children_query: Query<&Children>,
    mesh_query: Query<(&Mesh3d, &GlobalTransform)>,
    meshes: Res<Assets<Mesh>>,
) {
    if preview_state.load_status != PreviewLoadStatus::Ready {
        return;
    }
    let Some(model_path) = preview_state.applied_model_path.as_ref() else {
        return;
    };
    if preview_state.framed_model_path.as_deref() == Some(model_path.as_str()) {
        return;
    }
    let Some(scene_root) = preview_state.scene_instance else {
        return;
    };

    let Some(bounds) = scene_world_bounds(scene_root, &children_query, &mesh_query, &meshes) else {
        return;
    };

    let size = bounds.size();
    let half_extents = size * 0.5;
    let vertical_half_fov = std::f32::consts::FRAC_PI_4 * 0.5;
    let target_fill = DEFAULT_MODEL_VIEWPORT_FILL.clamp(0.1, 0.95);
    let radius_y = half_extents.y.max(0.35) / (vertical_half_fov.tan() * target_fill);
    let radius_z = half_extents.z.max(0.35) * 1.35;
    let radius = radius_y
        .max(radius_z)
        .clamp(CAMERA_RADIUS_MIN, CAMERA_RADIUS_MAX);

    preview_camera.set_orbit(PreviewOrbitCamera {
        focus: bounds.center(),
        yaw_radians: -0.55,
        pitch_radians: -0.12,
        radius,
    });
    preview_state.framed_model_path = Some(model_path.clone());
}

fn scene_world_bounds(
    root: Entity,
    children_query: &Query<&Children>,
    mesh_query: &Query<(&Mesh3d, &GlobalTransform)>,
    meshes: &Assets<Mesh>,
) -> Option<SceneWorldBounds> {
    let mut stack = vec![root];
    let mut bounds: Option<SceneWorldBounds> = None;

    while let Some(entity) = stack.pop() {
        if let Ok((mesh_handle, transform)) = mesh_query.get(entity) {
            if let Some(mesh) = meshes.get(&mesh_handle.0) {
                if let Some(mesh_aabb) = mesh.compute_aabb() {
                    let center = Vec3::from(mesh_aabb.center);
                    let half_extents = Vec3::from(mesh_aabb.half_extents);
                    let affine = transform.affine();
                    for corner in [
                        Vec3::new(-half_extents.x, -half_extents.y, -half_extents.z),
                        Vec3::new(-half_extents.x, -half_extents.y, half_extents.z),
                        Vec3::new(-half_extents.x, half_extents.y, -half_extents.z),
                        Vec3::new(-half_extents.x, half_extents.y, half_extents.z),
                        Vec3::new(half_extents.x, -half_extents.y, -half_extents.z),
                        Vec3::new(half_extents.x, -half_extents.y, half_extents.z),
                        Vec3::new(half_extents.x, half_extents.y, -half_extents.z),
                        Vec3::new(half_extents.x, half_extents.y, half_extents.z),
                    ] {
                        let world_point = affine.transform_point3(center + corner);
                        match &mut bounds {
                            Some(world_bounds) => world_bounds.include_point(world_point),
                            None => bounds = Some(SceneWorldBounds::from_point(world_point)),
                        }
                    }
                }
            }
        }

        if let Ok(children) = children_query.get(entity) {
            for child in children.iter() {
                stack.push(child);
            }
        }
    }

    bounds
}

fn sync_preview_ground_visibility_system(
    ui_state: Res<ViewerUiState>,
    mut floor_query: Query<&mut Visibility, With<PreviewFloor>>,
) {
    let visibility = if ui_state.show_ground {
        Visibility::Visible
    } else {
        Visibility::Hidden
    };
    for mut floor_visibility in &mut floor_query {
        *floor_visibility = visibility;
    }
}

fn paint_axis_gizmo(ui: &mut egui::Ui, rect: egui::Rect, orbit: PreviewOrbitCamera) {
    let mut camera_transform = Transform::IDENTITY;
    apply_preview_orbit_camera(&mut camera_transform, orbit);

    let right = camera_transform.rotation * Vec3::X;
    let up = camera_transform.rotation * Vec3::Y;
    let forward = camera_transform.rotation * -Vec3::Z;
    let center = egui::pos2(rect.left() + 38.0, rect.bottom() - 38.0);
    let radius = 16.0;
    let painter = ui.painter();

    painter.circle_filled(
        center,
        24.0,
        egui::Color32::from_rgba_unmultiplied(18, 21, 28, 196),
    );
    painter.circle_stroke(
        center,
        24.0,
        egui::Stroke::new(
            1.0,
            egui::Color32::from_rgba_unmultiplied(210, 215, 224, 64),
        ),
    );

    let mut axes = [
        ("X", Vec3::X, egui::Color32::from_rgb(210, 61, 56)),
        ("Y", Vec3::Y, egui::Color32::from_rgb(72, 186, 92)),
        ("Z", Vec3::Z, egui::Color32::from_rgb(78, 124, 224)),
    ]
    .map(|(label, axis, color)| {
        let screen = egui::vec2(axis.dot(right), -axis.dot(up)) * radius;
        let depth = axis.dot(forward);
        (depth, label, color, center + screen)
    });
    axes.sort_by(|left, right| {
        left.0
            .partial_cmp(&right.0)
            .unwrap_or(std::cmp::Ordering::Equal)
    });

    for (_, label, color, end) in axes {
        painter.line_segment([center, end], egui::Stroke::new(2.0, color));
        painter.circle_filled(end, 3.0, color);
        painter.text(
            end + egui::vec2(6.0, 0.0),
            egui::Align2::LEFT_CENTER,
            label,
            egui::FontId::new(10.0, egui::FontFamily::Proportional),
            color,
        );
    }
}

fn collect_models(asset_root: &Path, current_dir: &Path, entries: &mut Vec<ModelEntry>) {
    let Ok(read_dir) = fs::read_dir(current_dir) else {
        return;
    };
    for entry in read_dir.flatten() {
        let path = entry.path();
        if path.is_dir() {
            collect_models(asset_root, &path, entries);
            continue;
        }
        let Some(extension) = path.extension().and_then(|value| value.to_str()) else {
            continue;
        };
        if extension != "gltf" {
            continue;
        }
        let Ok(relative) = path.strip_prefix(asset_root) else {
            continue;
        };
        let relative = relative.to_string_lossy().replace('\\', "/");
        entries.push(ModelEntry::new(relative));
    }
}
