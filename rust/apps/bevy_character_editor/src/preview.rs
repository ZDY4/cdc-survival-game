//! 预览协调层。
//! 负责角色选择、外观预览、AI 预览和相机状态之间的同步与刷新。

use bevy::log::{info, warn};
use bevy::prelude::*;
use game_bevy::resolve_item_preview_asset_path;
use game_data::{
    build_character_ai_preview, build_character_ai_preview_at_time,
    build_character_appearance_preview, CharacterAiPreviewContext, CharacterDefinition,
    CharacterId, SettlementDefinition, SettlementId, SettlementLibrary,
};
use game_editor::{
    character_preview_is_available, spawn_character_preview_scene, CharacterPreviewRoot,
    PreviewCameraController,
};

use crate::camera_mode::{
    default_orbit_for_mode, reset_active_preview_camera, sync_preview_camera_mode,
    PreviewCameraModeState,
};
use crate::state::{default_preview_context, EditorData, EditorUiState, PreviewState};

pub(crate) const CAMERA_RADIUS_MIN: f32 = 1.2;
pub(crate) const CAMERA_RADIUS_MAX: f32 = 8.0;
pub(crate) const PREVIEW_BG: Color = Color::srgb(0.095, 0.105, 0.125);

#[derive(Component)]
pub(crate) struct PreviewCamera;

// 仅在预览内容版本变化时重建场景实体。
pub(crate) fn sync_preview_scene_system(
    mut commands: Commands,
    asset_server: Res<AssetServer>,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
    mut preview_state: ResMut<PreviewState>,
    existing_roots: Query<Entity, With<CharacterPreviewRoot>>,
) {
    if preview_state.revision == preview_state.applied_revision {
        return;
    }
    for entity in &existing_roots {
        commands.entity(entity).despawn();
    }
    if let Some(preview) = preview_state
        .resolved_preview
        .as_ref()
        .filter(|preview| character_preview_has_explicit_gltf_model(preview))
    {
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

// 确保编辑器始终有一个默认选中的角色。
pub(crate) fn ensure_selected_character(
    data: &EditorData,
    ui_state: &mut EditorUiState,
    preview_state: &mut PreviewState,
    camera_mode: &mut PreviewCameraModeState,
    preview_camera: &mut PreviewCameraController,
    preview_projection: &mut Projection,
) {
    if ui_state.selected_character_id.is_none() {
        if let Some(summary) = data.character_summaries.first() {
            select_character(
                summary.id.clone(),
                data,
                ui_state,
                preview_state,
                camera_mode,
                preview_camera,
                preview_projection,
            );
        }
    }
}

// 切换当前角色，并重建默认上下文与预览状态。
pub(crate) fn select_character(
    character_id: String,
    data: &EditorData,
    ui_state: &mut EditorUiState,
    preview_state: &mut PreviewState,
    camera_mode: &mut PreviewCameraModeState,
    preview_camera: &mut PreviewCameraController,
    preview_projection: &mut Projection,
) {
    info!("character editor selected character: {character_id}");
    ui_state.selected_character_id = Some(character_id);
    ui_state.try_on.clear();
    ui_state.preview_context = selected_character(data, ui_state)
        .and_then(|character| default_context_for_character(character, data))
        .unwrap_or_else(default_preview_context);
    refresh_preview_state(
        data,
        ui_state,
        preview_state,
        camera_mode,
        preview_camera,
        preview_projection,
        true,
    );
}

// 刷新外观预览、AI 预览和提示文本，是编辑器的核心协调入口。
pub(crate) fn refresh_preview_state(
    data: &EditorData,
    ui_state: &mut EditorUiState,
    preview_state: &mut PreviewState,
    camera_mode: &mut PreviewCameraModeState,
    preview_camera: &mut PreviewCameraController,
    preview_projection: &mut Projection,
    reset_camera: bool,
) {
    preview_state.ai_preview = None;
    preview_state.ai_error = None;
    preview_state.appearance_error = None;
    preview_state.resolved_preview = None;
    preview_state.preview_notice = None;

    let Some(character) = selected_character(data, ui_state) else {
        ui_state.status = "未选择角色。".to_string();
        warn!("character editor refresh skipped: no selected character");
        if reset_camera {
            reset_active_preview_camera(camera_mode, None, preview_camera, preview_projection);
        }
        sync_preview_camera_mode(camera_mode, preview_camera, preview_projection);
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
            let next_orbit =
                reset_camera.then(|| default_orbit_for_mode(camera_mode.mode, Some(&preview)));
            if reset_camera {
                if let Some(next_orbit) = next_orbit {
                    preview_camera.set_orbit(next_orbit);
                }
            }
            if let Some(notice) = preview_model_notice(&preview) {
                warn!(
                    "character editor preview has no configured gltf model for character {}: {}",
                    character.id.as_str(),
                    preview.base_model_asset
                );
                preview_state.preview_notice = Some(notice);
            } else if !character_preview_is_available(&preview) {
                warn!(
                    "character editor preview model asset failed availability check for character {}: {}",
                    character.id.as_str(),
                    preview.base_model_asset
                );
                preview_state.preview_notice = Some(format!(
                    "当前角色配置的 glTF 模型不可用：{}",
                    preview.base_model_asset
                ));
            }
            preview_state.resolved_preview = Some(preview);
        }
        Err(error) => {
            warn!(
                "character editor appearance preview failed for {}: {}",
                character.id.as_str(),
                error
            );
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
                warn!(
                    "character editor ai preview failed for {}: {}",
                    character.id.as_str(),
                    error
                );
                preview_state.ai_error = Some(error.to_string());
            }
        }
    } else {
        warn!(
            "character editor ai preview unavailable for {}: ai library not loaded",
            character.id.as_str()
        );
        preview_state.ai_error = Some("AI 模块库未加载。".to_string());
    }

    ui_state.status = format!("已加载角色 {}", character.identity.display_name);
    info!(
        "character editor preview refreshed: {}",
        character.identity.display_name
    );
    sync_preview_camera_mode(camera_mode, preview_camera, preview_projection);
    preview_state.revision += 1;
}

// 从 UI 选中状态解析当前角色定义。
pub(crate) fn selected_character<'a>(
    data: &'a EditorData,
    ui_state: &EditorUiState,
) -> Option<&'a CharacterDefinition> {
    let id = ui_state.selected_character_id.as_ref()?;
    data.characters.get(&CharacterId(id.clone()))
}

// 根据角色 life profile 解析所在据点定义。
pub(crate) fn settlement_for_character<'a>(
    character: &CharacterDefinition,
    settlements: &'a SettlementLibrary,
) -> Option<&'a SettlementDefinition> {
    let settlement_id = character.life.as_ref()?.settlement_id.clone();
    settlements.get(&SettlementId(settlement_id))
}

// 基于角色静态配置推导 AI 预览默认上下文。
pub(crate) fn default_context_for_character(
    character: &CharacterDefinition,
    data: &EditorData,
) -> Option<CharacterAiPreviewContext> {
    let ai_library = data.ai_library.as_ref()?;
    let settlement = settlement_for_character(character, &data.settlements);
    build_character_ai_preview(character, settlement, ai_library)
        .map(|preview| preview.context)
        .ok()
}

fn character_preview_has_explicit_gltf_model(
    preview: &game_data::ResolvedCharacterAppearancePreview,
) -> bool {
    let asset_id = preview.base_model_asset.trim();
    asset_id.ends_with(".gltf") && resolve_item_preview_asset_path(asset_id).is_some()
}

fn preview_model_notice(preview: &game_data::ResolvedCharacterAppearancePreview) -> Option<String> {
    let asset_id = preview.base_model_asset.trim();
    if !asset_id.ends_with(".gltf") {
        return Some(
            "当前角色未配置 glTF 模型，请在 appearance profile 或 model_path 中填写角色模型。"
                .to_string(),
        );
    }
    if resolve_item_preview_asset_path(asset_id).is_none() {
        return Some(format!("当前角色配置的 glTF 模型不存在：{asset_id}"));
    }
    None
}
