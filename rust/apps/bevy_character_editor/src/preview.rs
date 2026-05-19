//! 预览协调层。
//! 负责角色选择、外观预览、AI 预览和相机状态之间的同步与刷新。

use std::collections::HashSet;

use bevy::camera::primitives::MeshAabb;
use bevy::log::{info, warn};
use bevy::prelude::*;
use game_bevy::{
    resolve_item_preview_asset_path, CharacterPreviewModelAsset, MeshPickIndex,
    MeshPickPrototypeKey,
};
use game_data::{
    build_character_ai_preview, build_character_ai_preview_at_time,
    build_character_appearance_preview, CharacterAiPreviewContext, CharacterDefinition,
    CharacterId, SettlementDefinition, SettlementId, SettlementLibrary,
};
use game_editor::{
    character_preview_is_available, draw_preview_pivot_gizmo, spawn_character_preview_scene,
    CharacterPreviewPart, CharacterPreviewRoot, PreviewCameraController, PreviewPivotVisibility,
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
        spawn_character_preview_scene(&mut commands, &asset_server, &mut materials, preview);
    }
    preview_state.applied_revision = preview_state.revision;
}

pub(crate) fn sync_preview_mesh_pick_index_system(
    mut pick_index: ResMut<MeshPickIndex<String>>,
    sources: Query<(Entity, &CharacterPreviewModelAsset), With<CharacterPreviewPart>>,
    children_query: Query<&Children>,
    mesh_query: Query<(&Mesh3d, &GlobalTransform, Option<&Visibility>)>,
    meshes: Res<Assets<Mesh>>,
) {
    pick_index.clear();
    let source_roots = sources
        .iter()
        .map(|(entity, _)| entity)
        .collect::<HashSet<_>>();
    for (root, source) in &sources {
        register_pick_tree(
            root,
            source.asset_path.as_str(),
            &source_roots,
            &children_query,
            &mesh_query,
            &meshes,
            &mut pick_index,
        );
    }
}

pub(crate) fn sync_preview_bounds_system(
    mut preview_state: ResMut<PreviewState>,
    root_query: Query<Entity, With<CharacterPreviewRoot>>,
    children_query: Query<&Children>,
    mesh_query: Query<(&Mesh3d, &GlobalTransform, Option<&Visibility>)>,
    meshes: Res<Assets<Mesh>>,
) {
    let Some(root) = root_query.iter().next() else {
        preview_state.model_size = None;
        return;
    };
    preview_state.model_size =
        scene_world_bounds(root, &children_query, &mesh_query, &meshes).map(|bounds| bounds.size());
}

pub(crate) fn draw_pivot_gizmo_system(
    pivot_visibility: Res<PreviewPivotVisibility>,
    root_query: Query<&GlobalTransform, With<CharacterPreviewRoot>>,
    mut gizmos: Gizmos,
) {
    if !pivot_visibility.visible {
        return;
    }
    let Some(transform) = root_query.iter().next() else {
        return;
    };
    let transform = transform.compute_transform();
    draw_preview_pivot_gizmo(&mut gizmos, transform.translation, transform.rotation);
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
    preview_state.model_size = None;

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

    fn size(self) -> Vec3 {
        self.max - self.min
    }
}

fn scene_world_bounds(
    root: Entity,
    children_query: &Query<&Children>,
    mesh_query: &Query<(&Mesh3d, &GlobalTransform, Option<&Visibility>)>,
    meshes: &Assets<Mesh>,
) -> Option<SceneWorldBounds> {
    let mut stack = vec![root];
    let mut bounds: Option<SceneWorldBounds> = None;

    while let Some(entity) = stack.pop() {
        if let Ok(children) = children_query.get(entity) {
            for child in children.iter() {
                stack.push(child);
            }
        }

        let Ok((mesh_handle, transform, visibility)) = mesh_query.get(entity) else {
            continue;
        };
        if matches!(visibility, Some(Visibility::Hidden)) {
            continue;
        }
        let Some(mesh) = meshes.get(&mesh_handle.0) else {
            continue;
        };
        let Some(mesh_aabb) = mesh.compute_aabb() else {
            continue;
        };
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

    bounds
}

fn register_pick_tree(
    root: Entity,
    asset_path: &str,
    source_roots: &HashSet<Entity>,
    children_query: &Query<&Children>,
    mesh_query: &Query<(&Mesh3d, &GlobalTransform, Option<&Visibility>)>,
    meshes: &Assets<Mesh>,
    pick_index: &mut MeshPickIndex<String>,
) {
    let mut stack = vec![root];
    while let Some(entity) = stack.pop() {
        if entity != root && source_roots.contains(&entity) {
            continue;
        }
        if let Ok(children) = children_query.get(entity) {
            for child in children.iter() {
                stack.push(child);
            }
        }

        let Ok((mesh_handle, transform, visibility)) = mesh_query.get(entity) else {
            continue;
        };
        if matches!(visibility, Some(Visibility::Hidden)) {
            continue;
        }
        let Some(mesh) = meshes.get(&mesh_handle.0) else {
            continue;
        };
        pick_index.register_mesh_instance_preserving_fallback(
            entity,
            mesh,
            MeshPickPrototypeKey::mesh(&mesh_handle.0),
            transform.compute_transform(),
            asset_path.to_string(),
        );
    }
}
