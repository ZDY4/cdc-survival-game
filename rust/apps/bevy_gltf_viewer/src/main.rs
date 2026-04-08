use std::fs;
use std::path::{Path, PathBuf};

use bevy::asset::LoadState;
use bevy::camera::{CameraOutputMode, ClearColorConfig, Viewport};
use bevy::ecs::message::MessageReader;
use bevy::input::mouse::{MouseMotion, MouseWheel};
use bevy::prelude::*;
use bevy::render::render_resource::BlendState;
use bevy_egui::input::EguiWantsInput;
use bevy_egui::{
    egui, EguiContexts, EguiGlobalSettings, EguiPlugin, EguiPrimaryContextPass, PrimaryEguiContext,
};
use game_bevy::{
    apply_preview_orbit_camera, game_ui_font_bytes, replace_preview_scene, spawn_preview_floor,
    spawn_preview_light_rig, spawn_preview_origin_axes, spawn_preview_scene_host,
    PreviewOrbitCamera, GAME_UI_FONT_NAME,
};

const PREVIEW_BG: Color = Color::srgb(0.095, 0.105, 0.125);
const MODEL_PANEL_WIDTH: f32 = 320.0;
const CAMERA_RADIUS_MIN: f32 = 0.8;
const CAMERA_RADIUS_MAX: f32 = 18.0;

fn main() {
    App::new()
        .add_plugins(
            DefaultPlugins
                .set(WindowPlugin {
                    primary_window: Some(Window {
                        title: "CDC glTF Viewer".into(),
                        resolution: (1600, 920).into(),
                        ..default()
                    }),
                    ..default()
                })
                .set(AssetPlugin {
                    file_path: gltf_viewer_asset_dir().display().to_string(),
                    ..default()
                }),
        )
        .add_plugins(EguiPlugin::default())
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
                preview_camera_input_system,
                sync_preview_scene_system,
                refresh_preview_load_status_system,
                update_preview_camera_system,
            )
                .chain(),
        )
        .run();
}

fn gltf_viewer_asset_dir() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../assets")
}

#[derive(Debug, Clone, Copy, Default)]
struct ViewportRect {
    min_x: f32,
    min_y: f32,
    width: f32,
    height: f32,
}

impl ViewportRect {
    fn contains(self, cursor: Vec2) -> bool {
        cursor.x >= self.min_x
            && cursor.x <= self.min_x + self.width
            && cursor.y >= self.min_y
            && cursor.y <= self.min_y + self.height
    }
}

#[derive(Debug, Clone)]
struct ModelEntry {
    relative_path: String,
    search_text: String,
}

impl ModelEntry {
    fn new(relative_path: String) -> Self {
        Self {
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
    viewport_rect: Option<ViewportRect>,
    orbit_camera: PreviewOrbitCamera,
}

impl Default for ViewerUiState {
    fn default() -> Self {
        Self {
            search_text: String::new(),
            selected_model_path: None,
            viewport_rect: None,
            orbit_camera: PreviewOrbitCamera {
                focus: Vec3::new(0.0, 0.7, 0.0),
                yaw_radians: -0.55,
                pitch_radians: -0.18,
                radius: 4.4,
            },
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
    spawn_preview_origin_axes(&mut commands, &mut meshes, &mut materials, 1.25, 0.028);
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

    let mut fonts = egui::FontDefinitions::default();
    fonts.font_data.insert(
        GAME_UI_FONT_NAME.to_string(),
        egui::FontData::from_owned(game_ui_font_bytes().to_vec()).into(),
    );
    for family in [egui::FontFamily::Proportional, egui::FontFamily::Monospace] {
        fonts
            .families
            .entry(family)
            .or_default()
            .insert(0, GAME_UI_FONT_NAME.to_string());
    }
    ctx.set_fonts(fonts);

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
                    if ui
                        .selectable_label(selected, entry.relative_path.as_str())
                        .clicked()
                    {
                        ui_state.selected_model_path = Some(entry.relative_path.clone());
                        ui_state.orbit_camera = ViewerUiState::default().orbit_camera;
                    }
                }
            });
        });

    egui::CentralPanel::default()
        .frame(egui::Frame::NONE)
        .show(ctx, |ui| {
            let rect = ui.max_rect();
            ui_state.viewport_rect = Some(ViewportRect {
                min_x: rect.min.x,
                min_y: rect.min.y,
                width: rect.width(),
                height: rect.height(),
            });
            ui.allocate_rect(rect, egui::Sense::hover());
            ui.painter()
                .rect_filled(rect, 0.0, egui::Color32::from_rgb(18, 21, 28));
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
        });

    if preview_state.requested_model_path != ui_state.selected_model_path {
        preview_state.requested_model_path = ui_state.selected_model_path.clone();
    }
}

fn preview_camera_input_system(
    mouse_buttons: Res<ButtonInput<MouseButton>>,
    egui_wants_input: Res<EguiWantsInput>,
    mut mouse_motion: MessageReader<MouseMotion>,
    mut mouse_wheel: MessageReader<MouseWheel>,
    window: Single<&Window>,
    mut ui_state: ResMut<ViewerUiState>,
) {
    let Some(viewport) = ui_state.viewport_rect else {
        return;
    };
    let Some(cursor) = window.cursor_position() else {
        return;
    };
    if !viewport.contains(cursor) {
        mouse_motion.clear();
        mouse_wheel.clear();
        return;
    }
    if egui_wants_input.wants_any_pointer_input() {
        return;
    }

    if mouse_buttons.pressed(MouseButton::Left) {
        for event in mouse_motion.read() {
            ui_state.orbit_camera.yaw_radians -= event.delta.x * 0.012;
            ui_state.orbit_camera.pitch_radians =
                (ui_state.orbit_camera.pitch_radians - event.delta.y * 0.008).clamp(-1.2, 0.72);
        }
    } else {
        mouse_motion.clear();
    }

    for event in mouse_wheel.read() {
        ui_state.orbit_camera.radius = (ui_state.orbit_camera.radius - event.y * 0.24)
            .clamp(CAMERA_RADIUS_MIN, CAMERA_RADIUS_MAX);
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
        preview_state.load_status = PreviewLoadStatus::Idle;
        return;
    };

    let (_, handle) = replace_preview_scene(
        &mut commands,
        &asset_server,
        host_entity,
        &mut preview_state.scene_instance,
        path.clone(),
    );
    preview_state.scene_handle = Some(handle);
    preview_state.applied_model_path = Some(path);
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

fn update_preview_camera_system(
    window: Single<&Window>,
    ui_state: Res<ViewerUiState>,
    mut camera_query: Single<(&mut Camera, &mut Transform), With<PreviewCamera>>,
) {
    let (camera, transform) = &mut *camera_query;
    if let Some(rect) = ui_state.viewport_rect {
        let scale_factor = window.scale_factor() as f32;
        let min_x = rect.min_x * scale_factor;
        let min_y = rect.min_y * scale_factor;
        let width = rect.width * scale_factor;
        let height = rect.height * scale_factor;
        let max_width = window.physical_width() as f32;
        let max_height = window.physical_height() as f32;
        let physical_position = UVec2::new(
            min_x.clamp(0.0, (max_width - 1.0).max(0.0)) as u32,
            min_y.clamp(0.0, (max_height - 1.0).max(0.0)) as u32,
        );
        let physical_size = UVec2::new(
            width.clamp(1.0, (max_width - physical_position.x as f32).max(1.0)) as u32,
            height.clamp(1.0, (max_height - physical_position.y as f32).max(1.0)) as u32,
        );
        camera.viewport = Some(Viewport {
            physical_position,
            physical_size,
            depth: 0.0..1.0,
        });
    }
    apply_preview_orbit_camera(transform, ui_state.orbit_camera);
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
        if !matches!(extension, "gltf" | "glb") {
            continue;
        }
        let Ok(relative) = path.strip_prefix(asset_root) else {
            continue;
        };
        let relative = relative.to_string_lossy().replace('\\', "/");
        entries.push(ModelEntry::new(relative));
    }
}
