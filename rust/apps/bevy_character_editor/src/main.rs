use std::collections::BTreeMap;
use std::path::PathBuf;

use bevy::camera::Viewport;
use bevy::ecs::message::MessageReader;
use bevy::input::mouse::{MouseMotion, MouseWheel};
use bevy::prelude::*;
use bevy_egui::input::EguiWantsInput;
use bevy_egui::{egui, EguiContexts, EguiPlugin, EguiPrimaryContextPass};
use game_bevy::{
    apply_preview_orbit_camera, game_ui_font_bytes, spawn_character_preview_light_rig,
    spawn_character_preview_scene, CharacterPreviewPart, CharacterPreviewPlugin,
    PreviewOrbitCamera, GAME_UI_FONT_NAME,
};
use game_data::{
    build_character_ai_preview, build_character_ai_preview_at_time,
    build_character_appearance_preview, load_ai_module_library, load_character_appearance_library,
    load_character_library, load_effect_library, load_item_library, load_settlement_library,
    validate_ai_content, validate_character_appearance_content, AiModuleLibrary,
    CharacterAiPreview, CharacterAiPreviewContext, CharacterAppearanceLibrary, CharacterDefinition,
    CharacterId, CharacterLibrary, ItemLibrary, NpcRole, ResolvedCharacterAppearancePreview,
    ScheduleDay, SettlementDefinition, SettlementId, SettlementLibrary,
};

const LIST_PANEL_WIDTH: f32 = 250.0;
const DETAIL_PANEL_WIDTH: f32 = 430.0;
const CAMERA_RADIUS_MIN: f32 = 1.2;
const CAMERA_RADIUS_MAX: f32 = 8.0;
const PREVIEW_BG: Color = Color::srgb(0.095, 0.105, 0.125);

fn main() {
    App::new()
        .add_plugins(
            DefaultPlugins
                .set(WindowPlugin {
                    primary_window: Some(Window {
                        title: "CDC Character Editor".into(),
                        resolution: (1720, 980).into(),
                        ..default()
                    }),
                    ..default()
                })
                .set(AssetPlugin {
                    file_path: character_editor_asset_dir().display().to_string(),
                    ..default()
                }),
        )
        .add_plugins(EguiPlugin::default())
        .add_plugins(CharacterPreviewPlugin)
        .insert_resource(ClearColor(PREVIEW_BG))
        .insert_resource(load_editor_data())
        .insert_resource(EditorUiState::default())
        .insert_resource(PreviewState::default())
        .insert_resource(EditorEguiFontState::default())
        .add_systems(Startup, setup_editor)
        .add_systems(
            EguiPrimaryContextPass,
            (configure_egui_fonts_system, editor_ui_system).chain(),
        )
        .add_systems(
            Update,
            (
                sync_preview_scene_system,
                preview_camera_input_system,
                update_preview_camera_system,
            )
                .chain(),
        )
        .run();
}

fn character_editor_asset_dir() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../assets")
}

#[derive(Resource, Default)]
struct EditorEguiFontState {
    initialized: bool,
}

#[derive(Resource)]
struct EditorData {
    repo_root: PathBuf,
    characters: CharacterLibrary,
    items: ItemLibrary,
    settlements: SettlementLibrary,
    ai_library: Option<AiModuleLibrary>,
    appearance_library: CharacterAppearanceLibrary,
    character_summaries: Vec<CharacterSummary>,
    item_catalog_by_slot: BTreeMap<String, Vec<ItemChoice>>,
    warnings: Vec<String>,
}

#[derive(Debug, Clone)]
struct CharacterSummary {
    id: String,
    display_name: String,
    settlement_id: String,
    role: String,
    behavior_profile_id: String,
}

#[derive(Debug, Clone)]
struct ItemChoice {
    id: u32,
    name: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum CharacterTab {
    Summary,
    Life,
    AiPreview,
    Appearance,
}

#[derive(Debug, Clone, Copy, Default)]
struct ViewportRect {
    min_x: f32,
    min_y: f32,
    width: f32,
    height: f32,
}

impl ViewportRect {
    fn contains(&self, cursor: Vec2) -> bool {
        cursor.x >= self.min_x
            && cursor.x <= self.min_x + self.width
            && cursor.y >= self.min_y
            && cursor.y <= self.min_y + self.height
    }
}

#[derive(Resource)]
struct EditorUiState {
    search_text: String,
    selected_character_id: Option<String>,
    selected_tab: CharacterTab,
    selected_slot: String,
    try_on: BTreeMap<String, u32>,
    preview_context: CharacterAiPreviewContext,
    viewport_rect: Option<ViewportRect>,
    orbit_camera: PreviewOrbitCamera,
    status: String,
}

impl Default for EditorUiState {
    fn default() -> Self {
        Self {
            search_text: String::new(),
            selected_character_id: None,
            selected_tab: CharacterTab::Summary,
            selected_slot: "main_hand".to_string(),
            try_on: BTreeMap::new(),
            preview_context: default_preview_context(),
            viewport_rect: None,
            orbit_camera: PreviewOrbitCamera::default(),
            status: "加载角色数据中…".to_string(),
        }
    }
}

#[derive(Resource, Default)]
struct PreviewState {
    revision: u64,
    applied_revision: u64,
    resolved_preview: Option<ResolvedCharacterAppearancePreview>,
    ai_preview: Option<CharacterAiPreview>,
    ai_error: Option<String>,
    appearance_error: Option<String>,
}

#[derive(Component)]
struct PreviewCamera;

#[derive(Component)]
struct PreviewFloor;

fn setup_editor(
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
) {
    spawn_character_preview_light_rig(&mut commands);
    commands.spawn((
        Camera3d::default(),
        Camera {
            order: 0,
            ..default()
        },
        Projection::Perspective(PerspectiveProjection {
            fov: std::f32::consts::FRAC_PI_4,
            near: 0.01,
            far: 100.0,
            ..default()
        }),
        Transform::from_xyz(2.2, 1.6, 3.0).looking_at(Vec3::new(0.0, 0.95, 0.0), Vec3::Y),
        PreviewCamera,
    ));
    commands.spawn((
        Mesh3d(meshes.add(Cuboid::new(5.0, 0.06, 5.0))),
        MeshMaterial3d(materials.add(StandardMaterial {
            base_color: Color::srgb(0.22, 0.235, 0.26),
            perceptual_roughness: 0.94,
            metallic: 0.02,
            ..default()
        })),
        Transform::from_xyz(0.0, -0.03, 0.0),
        PreviewFloor,
    ));
}

fn configure_egui_fonts_system(
    mut contexts: EguiContexts,
    mut font_state: ResMut<EditorEguiFontState>,
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
    style.spacing.button_padding = egui::vec2(8.0, 4.0);
    style.visuals.widgets.noninteractive.corner_radius = 4.0.into();
    style.visuals.widgets.inactive.corner_radius = 4.0.into();
    style.visuals.widgets.hovered.corner_radius = 4.0.into();
    style.visuals.widgets.active.corner_radius = 4.0.into();
    style.text_styles.insert(
        egui::TextStyle::Heading,
        egui::FontId::new(18.0, egui::FontFamily::Proportional),
    );
    style.text_styles.insert(
        egui::TextStyle::Body,
        egui::FontId::new(13.0, egui::FontFamily::Proportional),
    );
    style.text_styles.insert(
        egui::TextStyle::Button,
        egui::FontId::new(12.0, egui::FontFamily::Proportional),
    );
    style.text_styles.insert(
        egui::TextStyle::Small,
        egui::FontId::new(11.0, egui::FontFamily::Proportional),
    );
    ctx.set_style(style);
    font_state.initialized = true;
}

fn editor_ui_system(
    mut contexts: EguiContexts,
    data: Res<EditorData>,
    mut ui_state: ResMut<EditorUiState>,
    mut preview_state: ResMut<PreviewState>,
) {
    let ctx = contexts
        .ctx_mut()
        .expect("primary egui context should exist for the character editor");

    ensure_selected_character(&data, &mut ui_state, &mut preview_state);

    egui::TopBottomPanel::top("character_editor_topbar").show(ctx, |ui| {
        ui.horizontal(|ui| {
            ui.heading("角色编辑器");
            ui.separator();
            ui.label(format!("角色 {}", data.character_summaries.len()));
            ui.separator();
            ui.small(format!("仓库 {}", data.repo_root.display()));
            if !data.warnings.is_empty() {
                ui.separator();
                ui.colored_label(
                    egui::Color32::from_rgb(220, 170, 72),
                    format!("诊断 {}", data.warnings.len()),
                )
                .on_hover_text(data.warnings.join("\n"));
            }
            ui.separator();
            ui.small(&ui_state.status);
        });
    });

    egui::SidePanel::left("character_list")
        .default_width(LIST_PANEL_WIDTH)
        .resizable(true)
        .show(ctx, |ui| {
            render_character_list_panel(ui, &data, &mut ui_state, &mut preview_state);
        });

    egui::SidePanel::left("character_details")
        .default_width(DETAIL_PANEL_WIDTH)
        .resizable(true)
        .show(ctx, |ui| {
            render_detail_panel(ui, &data, &mut ui_state, &mut preview_state);
        });

    egui::CentralPanel::default().show(ctx, |ui| {
        let rect = ui.max_rect();
        ui_state.viewport_rect = Some(ViewportRect {
            min_x: rect.left(),
            min_y: rect.top(),
            width: rect.width(),
            height: rect.height(),
        });
        ui.allocate_rect(rect, egui::Sense::hover());
        ui.painter()
            .rect_filled(rect, 0.0, egui::Color32::from_rgb(18, 21, 28));
        ui.painter().text(
            rect.left_top() + egui::vec2(14.0, 12.0),
            egui::Align2::LEFT_TOP,
            "角色外观预览",
            egui::FontId::new(14.0, egui::FontFamily::Proportional),
            egui::Color32::from_rgb(228, 231, 238),
        );
        ui.painter().text(
            rect.left_top() + egui::vec2(14.0, 32.0),
            egui::Align2::LEFT_TOP,
            "左键拖拽旋转，滚轮缩放，右侧页签中可切换试装槽位。",
            egui::FontId::new(11.0, egui::FontFamily::Proportional),
            egui::Color32::from_rgb(164, 170, 184),
        );
    });
}

fn render_character_list_panel(
    ui: &mut egui::Ui,
    data: &EditorData,
    ui_state: &mut EditorUiState,
    preview_state: &mut PreviewState,
) {
    ui.horizontal(|ui| {
        ui.label("搜索");
        ui.add(
            egui::TextEdit::singleline(&mut ui_state.search_text)
                .hint_text("角色名 / ID")
                .desired_width(f32::INFINITY),
        );
    });
    ui.separator();

    let needle = ui_state.search_text.trim().to_lowercase();
    egui::ScrollArea::vertical()
        .auto_shrink([false, false])
        .show(ui, |ui| {
            for summary in &data.character_summaries {
                if !needle.is_empty()
                    && !summary.display_name.to_lowercase().contains(&needle)
                    && !summary.id.to_lowercase().contains(&needle)
                {
                    continue;
                }

                let selected =
                    ui_state.selected_character_id.as_deref() == Some(summary.id.as_str());
                let response = ui.selectable_label(
                    selected,
                    format!("{}  [{}]", summary.display_name, summary.id),
                );
                let response = response.on_hover_text(format!(
                    "据点: {}\n角色职责: {}\n行为包: {}",
                    non_empty(&summary.settlement_id),
                    non_empty(&summary.role),
                    non_empty(&summary.behavior_profile_id)
                ));
                if response.clicked() {
                    select_character(summary.id.clone(), data, ui_state, preview_state);
                }
            }
        });
}

fn render_detail_panel(
    ui: &mut egui::Ui,
    data: &EditorData,
    ui_state: &mut EditorUiState,
    preview_state: &mut PreviewState,
) {
    let Some(character) = selected_character(data, ui_state) else {
        ui.label("没有可用角色数据。");
        return;
    };

    ui.horizontal(|ui| {
        ui.heading(format!(
            "{}  [{}]",
            character.identity.display_name,
            character.id.as_str()
        ));
        if ui
            .small_button("重置相机")
            .on_hover_text("将预览相机重置到标准角色视角。")
            .clicked()
        {
            reset_orbit_from_current_preview(ui_state, preview_state);
        }
        if ui
            .small_button("清空试装")
            .on_hover_text("清空所有临时试装槽位，仅显示角色基础外观。")
            .clicked()
        {
            ui_state.try_on.clear();
            refresh_preview_state(data, ui_state, preview_state);
        }
    });
    ui.small(format!(
        "{} / {} / {}",
        archetype_label(character),
        disposition_label(character),
        non_empty(&character.faction.camp_id)
    ));
    ui.separator();

    ui.horizontal_wrapped(|ui| {
        tab_button(ui, ui_state, CharacterTab::Summary, "摘要");
        tab_button(ui, ui_state, CharacterTab::Life, "生活");
        tab_button(ui, ui_state, CharacterTab::AiPreview, "AI 预览");
        tab_button(ui, ui_state, CharacterTab::Appearance, "外观");
    });
    ui.separator();

    egui::ScrollArea::vertical()
        .auto_shrink([false, false])
        .show(ui, |ui| match ui_state.selected_tab {
            CharacterTab::Summary => render_summary_tab(ui, character),
            CharacterTab::Life => render_life_tab(ui, character, data),
            CharacterTab::AiPreview => render_ai_tab(ui, character, data, ui_state, preview_state),
            CharacterTab::Appearance => {
                render_appearance_tab(ui, character, data, ui_state, preview_state)
            }
        });
}

fn render_summary_tab(ui: &mut egui::Ui, character: &CharacterDefinition) {
    key_value(ui, "原型", archetype_label(character));
    key_value(ui, "阵营关系", disposition_label(character));
    key_value(ui, "阵营", non_empty(&character.faction.camp_id));
    key_value(ui, "等级", &character.progression.level.to_string());
    key_value(ui, "战斗行为", non_empty(&character.combat.behavior));
    key_value(ui, "经验奖励", &character.combat.xp_reward.to_string());
    key_value(ui, "外观配置", non_empty(&character.appearance_profile_id));
    if !character.identity.description.trim().is_empty() {
        ui.separator();
        ui.label(&character.identity.description);
    }
}

fn render_life_tab(ui: &mut egui::Ui, character: &CharacterDefinition, data: &EditorData) {
    let Some(life) = character.life.as_ref() else {
        ui.label("该角色没有 life profile。");
        return;
    };
    key_value(ui, "据点", non_empty(&life.settlement_id));
    key_value(ui, "角色职责", npc_role_label(life.role));
    key_value(ui, "行为包", non_empty(&life.ai_behavior_profile_id));
    key_value(ui, "日程模板", non_empty(&life.schedule_profile_id));
    key_value(ui, "性格模板", non_empty(&life.personality_profile_id));
    key_value(ui, "需求模板", non_empty(&life.need_profile_id));
    key_value(
        ui,
        "智能物体访问",
        non_empty(&life.smart_object_access_profile_id),
    );
    key_value(ui, "家锚点", non_empty(&life.home_anchor));
    key_value(ui, "执勤路线", non_empty(&life.duty_route_id));

    if let Some(settlement) = data
        .settlements
        .get(&SettlementId(life.settlement_id.clone()))
    {
        ui.separator();
        ui.collapsing("据点引用详情", |ui| {
            key_value(ui, "地图", settlement.map_id.as_str());
            key_value(ui, "锚点数", &settlement.anchors.len().to_string());
            key_value(ui, "路线数", &settlement.routes.len().to_string());
            key_value(
                ui,
                "智能物体数",
                &settlement.smart_objects.len().to_string(),
            );
            key_value(
                ui,
                "最低值班守卫",
                &settlement.service_rules.min_guard_on_duty.to_string(),
            );
        });
    }
}

fn render_ai_tab(
    ui: &mut egui::Ui,
    character: &CharacterDefinition,
    data: &EditorData,
    ui_state: &mut EditorUiState,
    preview_state: &mut PreviewState,
) {
    let mut changed = false;
    ui.horizontal(|ui| {
        ui.label("星期");
        egui::ComboBox::from_id_salt("preview_day")
            .selected_text(schedule_day_label(ui_state.preview_context.day))
            .show_ui(ui, |ui| {
                for day in [
                    ScheduleDay::Monday,
                    ScheduleDay::Tuesday,
                    ScheduleDay::Wednesday,
                    ScheduleDay::Thursday,
                    ScheduleDay::Friday,
                    ScheduleDay::Saturday,
                    ScheduleDay::Sunday,
                ] {
                    changed |= ui
                        .selectable_value(
                            &mut ui_state.preview_context.day,
                            day,
                            schedule_day_label(day),
                        )
                        .changed();
                }
            });
        changed |= ui
            .add(
                egui::Slider::new(&mut ui_state.preview_context.minute_of_day, 0..=1439)
                    .text("分钟"),
            )
            .changed();
    });
    ui.horizontal(|ui| {
        changed |= ui
            .add(egui::Slider::new(&mut ui_state.preview_context.hunger, 0.0..=100.0).text("饥饿"))
            .changed();
        changed |= ui
            .add(egui::Slider::new(&mut ui_state.preview_context.energy, 0.0..=100.0).text("精力"))
            .changed();
        changed |= ui
            .add(egui::Slider::new(&mut ui_state.preview_context.morale, 0.0..=100.0).text("士气"))
            .changed();
    });
    ui.horizontal(|ui| {
        changed |= ui
            .checkbox(&mut ui_state.preview_context.world_alert_active, "世界警报")
            .changed();
        changed |= ui
            .add(
                egui::TextEdit::singleline(
                    ui_state
                        .preview_context
                        .current_anchor
                        .get_or_insert_with(String::new),
                )
                .hint_text("当前锚点"),
            )
            .changed();
    });
    if changed {
        refresh_preview_state(data, ui_state, preview_state);
    }

    ui.separator();
    if let Some(error) = &preview_state.ai_error {
        ui.colored_label(egui::Color32::from_rgb(240, 110, 110), error);
        return;
    }
    let Some(preview) = preview_state.ai_preview.as_ref() else {
        ui.label("当前没有 AI 预览结果。");
        return;
    };
    ui.collapsing("性格", |ui| {
        key_value(ui, "配置", &preview.personality.id);
        key_value(
            ui,
            "安全偏好",
            &format!("{:.2}", preview.personality.safety_bias),
        );
        key_value(
            ui,
            "社交偏好",
            &format!("{:.2}", preview.personality.social_bias),
        );
        key_value(
            ui,
            "职责偏好",
            &format!("{:.2}", preview.personality.duty_bias),
        );
        key_value(
            ui,
            "舒适偏好",
            &format!("{:.2}", preview.personality.comfort_bias),
        );
        key_value(
            ui,
            "警觉偏好",
            &format!("{:.2}", preview.personality.alertness_bias),
        );
    });
    ui.collapsing("日程", |ui| {
        key_value(ui, "模板", &preview.schedule.profile_id);
        for entry in &preview.schedule.entries {
            ui.small(format!(
                "{} [{}-{}] {}",
                entry.label,
                entry.start_minute,
                entry.end_minute,
                entry.tags.join(", ")
            ));
        }
    });
    ui.collapsing("行为包", |ui| {
        key_value(ui, "行为", &preview.behavior.id);
        key_value(
            ui,
            "默认目标",
            preview.behavior.default_goal_id.as_deref().unwrap_or("-"),
        );
        key_value(
            ui,
            "警报目标",
            preview.behavior.alert_goal_id.as_deref().unwrap_or("-"),
        );
        key_value(ui, "Facts", &preview.behavior.facts.len().to_string());
        key_value(ui, "Goals", &preview.behavior.goals.len().to_string());
        key_value(ui, "Actions", &preview.behavior.actions.len().to_string());
    });
    ui.collapsing("决策快照", |ui| {
        ui.label("命中 Facts");
        ui.horizontal_wrapped(|ui| {
            for fact_id in &preview.fact_ids {
                let _ = ui.small_button(fact_id);
            }
        });
        ui.separator();
        ui.label("Goal 评分");
        for goal in &preview.goal_scores {
            ui.small(format!(
                "{} [{}] -> {}  ({})",
                goal.display_name,
                goal.goal_id,
                goal.score,
                goal.matched_rule_ids.join(", ")
            ));
        }
        ui.separator();
        ui.label("Action 可用性");
        for action in &preview.available_actions {
            ui.small(format!(
                "{} [{}] {} {}",
                action.display_name,
                action.action_id,
                if action.available { "可用" } else { "阻断" },
                action.blocked_by.join(", ")
            ));
        }
    });
    let _ = character;
}

fn render_appearance_tab(
    ui: &mut egui::Ui,
    character: &CharacterDefinition,
    data: &EditorData,
    ui_state: &mut EditorUiState,
    preview_state: &mut PreviewState,
) {
    key_value(ui, "外观配置", non_empty(&character.appearance_profile_id));
    if let Some(preview) = preview_state.resolved_preview.as_ref() {
        key_value(ui, "基础模型", &preview.base_model_asset);
        key_value(ui, "相机预设", &preview.preview_camera_preset_id);
        key_value(ui, "挂点预设", &preview.equip_anchor_profile_id);
        key_value(ui, "隐藏区域", &preview.hidden_base_regions.join(", "));
        if !preview.diagnostics.is_empty() {
            ui.colored_label(
                egui::Color32::from_rgb(224, 176, 72),
                preview.diagnostics.join("\n"),
            );
        }
    }
    if let Some(error) = &preview_state.appearance_error {
        ui.colored_label(egui::Color32::from_rgb(240, 110, 110), error);
    }
    ui.separator();
    ui.horizontal(|ui| {
        ui.label("当前槽位");
        egui::ComboBox::from_id_salt("appearance_slot")
            .selected_text(&ui_state.selected_slot)
            .show_ui(ui, |ui| {
                for slot in data.item_catalog_by_slot.keys() {
                    ui.selectable_value(&mut ui_state.selected_slot, slot.clone(), slot);
                }
            });
    });
    if let Some(items) = data.item_catalog_by_slot.get(&ui_state.selected_slot) {
        let selected_text = ui_state
            .try_on
            .get(&ui_state.selected_slot)
            .and_then(|item_id| items.iter().find(|item| item.id == *item_id))
            .map(|item| format!("{} [{}]", item.name, item.id))
            .unwrap_or_else(|| "未装备".to_string());
        egui::ComboBox::from_id_salt("appearance_choice")
            .selected_text(selected_text)
            .show_ui(ui, |ui| {
                if ui
                    .selectable_label(
                        !ui_state.try_on.contains_key(&ui_state.selected_slot),
                        "未装备",
                    )
                    .clicked()
                {
                    ui_state.try_on.remove(&ui_state.selected_slot);
                    refresh_preview_state(data, ui_state, preview_state);
                }
                for item in items {
                    if ui
                        .selectable_label(
                            ui_state.try_on.get(&ui_state.selected_slot) == Some(&item.id),
                            format!("{} [{}]", item.name, item.id),
                        )
                        .clicked()
                    {
                        ui_state
                            .try_on
                            .insert(ui_state.selected_slot.clone(), item.id);
                        refresh_preview_state(data, ui_state, preview_state);
                    }
                }
            });
    }
}

fn tab_button(ui: &mut egui::Ui, ui_state: &mut EditorUiState, tab: CharacterTab, label: &str) {
    if ui
        .selectable_label(ui_state.selected_tab == tab, label)
        .clicked()
    {
        ui_state.selected_tab = tab;
    }
}

fn key_value(ui: &mut egui::Ui, label: &str, value: &str) {
    ui.horizontal(|ui| {
        ui.small(format!("{label}:"));
        ui.label(value);
    });
}

fn sync_preview_scene_system(
    mut commands: Commands,
    asset_server: Res<AssetServer>,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
    mut preview_state: ResMut<PreviewState>,
    existing_parts: Query<Entity, With<CharacterPreviewPart>>,
) {
    if preview_state.revision == preview_state.applied_revision {
        return;
    }
    for entity in &existing_parts {
        commands.entity(entity).despawn();
    }
    if let Some(preview) = preview_state.resolved_preview.as_ref() {
        spawn_character_preview_scene(
            &mut commands,
            &asset_server,
            &mut meshes,
            &mut materials,
            preview,
        );
    }
    preview_state.applied_revision = preview_state.revision;
}

fn preview_camera_input_system(
    mouse_buttons: Res<ButtonInput<MouseButton>>,
    egui_wants_input: Res<EguiWantsInput>,
    mut mouse_motion: MessageReader<MouseMotion>,
    mut mouse_wheel: MessageReader<MouseWheel>,
    window: Single<&Window>,
    mut ui_state: ResMut<EditorUiState>,
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
                (ui_state.orbit_camera.pitch_radians - event.delta.y * 0.008).clamp(-1.1, 0.65);
        }
    } else {
        mouse_motion.clear();
    }

    for event in mouse_wheel.read() {
        ui_state.orbit_camera.radius = (ui_state.orbit_camera.radius - event.y * 0.16)
            .clamp(CAMERA_RADIUS_MIN, CAMERA_RADIUS_MAX);
    }
}

fn update_preview_camera_system(
    window: Single<&Window>,
    ui_state: Res<EditorUiState>,
    mut camera_query: Single<(&mut Camera, &mut Transform), With<PreviewCamera>>,
) {
    let (camera, transform) = &mut *camera_query;
    if let Some(rect) = ui_state.viewport_rect {
        let max_width = window.physical_width() as f32;
        let max_height = window.physical_height() as f32;
        let physical_position = UVec2::new(
            rect.min_x.clamp(0.0, (max_width - 1.0).max(0.0)) as u32,
            rect.min_y.clamp(0.0, (max_height - 1.0).max(0.0)) as u32,
        );
        let physical_size = UVec2::new(
            rect.width
                .clamp(1.0, (max_width - physical_position.x as f32).max(1.0)) as u32,
            rect.height
                .clamp(1.0, (max_height - physical_position.y as f32).max(1.0)) as u32,
        );
        camera.viewport = Some(Viewport {
            physical_position,
            physical_size,
            depth: 0.0..1.0,
        });
    }
    apply_preview_orbit_camera(transform, ui_state.orbit_camera);
}

fn load_editor_data() -> EditorData {
    let repo_root = repo_root();
    let character_dir = repo_root.join("data").join("characters");
    let effects_dir = repo_root.join("data").join("json").join("effects");
    let items_dir = repo_root.join("data").join("items");
    let ai_dir = repo_root.join("data").join("ai");
    let settlements_dir = repo_root.join("data").join("settlements");
    let appearance_dir = repo_root.join("data").join("appearance").join("characters");

    let mut warnings = Vec::new();
    let characters = load_character_library(&character_dir).unwrap_or_else(|error| {
        warnings.push(format!("角色库加载失败: {error}"));
        CharacterLibrary::default()
    });
    let effects = load_effect_library(&effects_dir).ok();
    let items = load_item_library(&items_dir, effects.as_ref()).unwrap_or_else(|error| {
        warnings.push(format!("物品库加载失败: {error}"));
        ItemLibrary::default()
    });
    let settlements = load_settlement_library(&settlements_dir).unwrap_or_else(|error| {
        warnings.push(format!("据点库加载失败: {error}"));
        SettlementLibrary::default()
    });
    let ai_library = match load_ai_module_library(&ai_dir) {
        Ok(library) => Some(library),
        Err(error) => {
            warnings.push(format!("AI 模块库加载失败: {error}"));
            None
        }
    };
    let appearance_library = if appearance_dir.exists() {
        load_character_appearance_library(&appearance_dir).unwrap_or_else(|error| {
            warnings.push(format!("外观配置加载失败: {error}"));
            CharacterAppearanceLibrary::default()
        })
    } else {
        CharacterAppearanceLibrary::default()
    };

    if let Some(ai_library) = ai_library.as_ref() {
        for issue in validate_ai_content(&characters, &settlements, ai_library) {
            warnings.push(format!("AI 校验 {}: {}", issue.severity, issue.message));
        }
    }
    for issue in validate_character_appearance_content(&characters, &items, &appearance_library) {
        warnings.push(format!("外观校验 {:?}: {}", issue.severity, issue.message));
    }

    let mut character_summaries = characters
        .iter()
        .map(|(id, definition)| CharacterSummary {
            id: id.as_str().to_string(),
            display_name: definition.identity.display_name.clone(),
            settlement_id: definition
                .life
                .as_ref()
                .map(|life| life.settlement_id.clone())
                .unwrap_or_default(),
            role: definition
                .life
                .as_ref()
                .map(|life| npc_role_label(life.role).to_string())
                .unwrap_or_default(),
            behavior_profile_id: definition
                .life
                .as_ref()
                .map(|life| life.ai_behavior_profile_id.clone())
                .unwrap_or_default(),
        })
        .collect::<Vec<_>>();
    character_summaries.sort_by(|left, right| {
        left.display_name
            .cmp(&right.display_name)
            .then_with(|| left.id.cmp(&right.id))
    });

    let mut item_catalog_by_slot = BTreeMap::<String, Vec<ItemChoice>>::new();
    for (_, item) in items.iter() {
        for slot in item.equip_slots() {
            item_catalog_by_slot
                .entry(slot)
                .or_default()
                .push(ItemChoice {
                    id: item.id,
                    name: item.name.clone(),
                });
        }
    }
    for entries in item_catalog_by_slot.values_mut() {
        entries.sort_by(|left, right| {
            left.name
                .cmp(&right.name)
                .then_with(|| left.id.cmp(&right.id))
        });
    }

    EditorData {
        repo_root,
        characters,
        items,
        settlements,
        ai_library,
        appearance_library,
        character_summaries,
        item_catalog_by_slot,
        warnings,
    }
}

fn repo_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../..")
}

fn ensure_selected_character(
    data: &EditorData,
    ui_state: &mut EditorUiState,
    preview_state: &mut PreviewState,
) {
    if ui_state.selected_character_id.is_none() {
        if let Some(summary) = data.character_summaries.first() {
            select_character(summary.id.clone(), data, ui_state, preview_state);
        }
    }
}

fn select_character(
    character_id: String,
    data: &EditorData,
    ui_state: &mut EditorUiState,
    preview_state: &mut PreviewState,
) {
    ui_state.selected_character_id = Some(character_id);
    ui_state.try_on.clear();
    ui_state.selected_slot = data
        .item_catalog_by_slot
        .keys()
        .next()
        .cloned()
        .unwrap_or_else(|| "main_hand".to_string());
    ui_state.preview_context = selected_character(data, ui_state)
        .and_then(|character| default_context_for_character(character, data))
        .unwrap_or_else(default_preview_context);
    refresh_preview_state(data, ui_state, preview_state);
}

fn refresh_preview_state(
    data: &EditorData,
    ui_state: &mut EditorUiState,
    preview_state: &mut PreviewState,
) {
    preview_state.ai_preview = None;
    preview_state.ai_error = None;
    preview_state.appearance_error = None;
    preview_state.resolved_preview = None;

    let Some(character) = selected_character(data, ui_state) else {
        ui_state.status = "未选择角色。".to_string();
        preview_state.revision += 1;
        return;
    };
    let character_id = CharacterId(character.id.as_str().to_string());
    match build_character_appearance_preview(
        &data.characters,
        &data.items,
        &data.appearance_library,
        &character_id,
        &ui_state.try_on,
    ) {
        Ok(preview) => {
            ui_state.orbit_camera = orbit_for_preview(&preview);
            preview_state.resolved_preview = Some(preview);
        }
        Err(error) => {
            preview_state.appearance_error = Some(error.to_string());
        }
    }

    if let Some(ai_library) = data.ai_library.as_ref() {
        let settlement = settlement_for_character(character, &data.settlements);
        match build_character_ai_preview_at_time(
            character,
            settlement,
            ai_library,
            &ui_state.preview_context,
        ) {
            Ok(preview) => {
                preview_state.ai_preview = Some(preview);
            }
            Err(error) => {
                preview_state.ai_error = Some(error.to_string());
            }
        }
    } else {
        preview_state.ai_error = Some("AI 模块库未加载。".to_string());
    }

    ui_state.status = format!("已加载角色 {}", character.identity.display_name);
    preview_state.revision += 1;
}

fn selected_character<'a>(
    data: &'a EditorData,
    ui_state: &EditorUiState,
) -> Option<&'a CharacterDefinition> {
    let id = ui_state.selected_character_id.as_ref()?;
    data.characters.get(&CharacterId(id.clone()))
}

fn settlement_for_character<'a>(
    character: &CharacterDefinition,
    settlements: &'a SettlementLibrary,
) -> Option<&'a SettlementDefinition> {
    let settlement_id = character.life.as_ref()?.settlement_id.clone();
    settlements.get(&SettlementId(settlement_id))
}

fn default_context_for_character(
    character: &CharacterDefinition,
    data: &EditorData,
) -> Option<CharacterAiPreviewContext> {
    let ai_library = data.ai_library.as_ref()?;
    let settlement = settlement_for_character(character, &data.settlements);
    build_character_ai_preview(character, settlement, ai_library)
        .map(|preview| preview.context)
        .ok()
}

fn default_preview_context() -> CharacterAiPreviewContext {
    CharacterAiPreviewContext {
        day: ScheduleDay::Monday,
        minute_of_day: 8 * 60,
        hunger: 20.0,
        energy: 80.0,
        morale: 65.0,
        world_alert_active: false,
        current_anchor: Some("home".to_string()),
        active_guards: 1,
        min_guard_on_duty: 1,
        availability: Default::default(),
    }
}

fn reset_orbit_from_current_preview(ui_state: &mut EditorUiState, preview_state: &PreviewState) {
    if let Some(preview) = preview_state.resolved_preview.as_ref() {
        ui_state.orbit_camera = orbit_for_preview(preview);
    } else {
        ui_state.orbit_camera = PreviewOrbitCamera::default();
    }
}

fn orbit_for_preview(preview: &ResolvedCharacterAppearancePreview) -> PreviewOrbitCamera {
    PreviewOrbitCamera {
        focus: Vec3::new(0.0, preview.preview_bounds.focus_y, 0.0),
        yaw_radians: -0.55,
        pitch_radians: -0.2,
        radius: (preview.preview_bounds.radius * 2.9).clamp(CAMERA_RADIUS_MIN, CAMERA_RADIUS_MAX),
    }
}

fn archetype_label(character: &CharacterDefinition) -> &'static str {
    match character.archetype {
        game_data::CharacterArchetype::Player => "玩家",
        game_data::CharacterArchetype::Npc => "NPC",
        game_data::CharacterArchetype::Enemy => "敌对单位",
    }
}

fn disposition_label(character: &CharacterDefinition) -> &'static str {
    match character.faction.disposition {
        game_data::CharacterDisposition::Player => "玩家",
        game_data::CharacterDisposition::Friendly => "友善",
        game_data::CharacterDisposition::Hostile => "敌对",
        game_data::CharacterDisposition::Neutral => "中立",
    }
}

fn npc_role_label(role: NpcRole) -> &'static str {
    match role {
        NpcRole::Guard => "守卫",
        NpcRole::Cook => "厨师",
        NpcRole::Doctor => "医生",
        NpcRole::Resident => "居民",
    }
}

fn schedule_day_label(day: ScheduleDay) -> &'static str {
    match day {
        ScheduleDay::Monday => "周一",
        ScheduleDay::Tuesday => "周二",
        ScheduleDay::Wednesday => "周三",
        ScheduleDay::Thursday => "周四",
        ScheduleDay::Friday => "周五",
        ScheduleDay::Saturday => "周六",
        ScheduleDay::Sunday => "周日",
    }
}

fn non_empty(value: &str) -> &str {
    if value.trim().is_empty() {
        "-"
    } else {
        value
    }
}
