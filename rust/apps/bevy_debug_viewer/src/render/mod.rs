//! 渲染模块门面：统一组织 viewer 的相机、世界可视化、战争迷雾、遮挡和屏幕叠加层子模块，
//! 并对外暴露 app 装配所需的稳定入口与共享渲染类型。

pub(super) use std::collections::{HashMap, HashSet};

pub(super) use bevy::asset::RenderAssetUsages;
pub(super) use bevy::light::{
    CascadeShadowConfigBuilder, DirectionalLightShadowMap, GlobalAmbientLight,
};
pub(super) use bevy::mesh::Indices;
pub(super) use bevy::pbr::{OpaqueRendererMethod, StandardMaterial};
use bevy::prelude::*;
pub(super) use bevy::render::render_resource::{
    Extent3d, PrimitiveTopology, ShaderType, TextureDimension, TextureFormat,
};
use bevy::ui::{ComputedNode, FocusPolicy, RelativeCursorPosition, UiGlobalTransform};
use game_bevy::{SettlementDebugEntry, SettlementDefinitions};
use game_data::{ActorId, ActorSide, GridCoord};

use crate::console::spawn_console_panel;
use crate::console::ViewerConsoleState;
use crate::dialogue::{current_dialogue_has_options, current_dialogue_node};
use crate::game_ui::{HOTBAR_DOCK_HEIGHT, HOTBAR_DOCK_WIDTH};
use crate::geometry::{
    actor_body_translation, actor_label, actor_label_world_position, camera_focus_point,
    camera_world_distance, clamp_camera_pan_offset, grid_bounds, grid_focus_world_position,
    hovered_grid_outline_kind, is_missing_generated_building, level_base_height,
    missing_geo_building_placeholder_box, occluder_blocks_target, rendered_path_preview,
    resolve_occlusion_focus_points, selected_actor, should_rebuild_static_world,
    viewer_grid_is_walkable, GridBounds, HoveredGridOutlineKind, OcclusionFocusPoint,
};
pub(super) use crate::picking::{pickable_target, ViewerPickBindingSpec, ViewerPickTarget};
use crate::state::{
    cursor_over_visible_ui_blocker, viewer_ui_passthrough_bundle, ActorLabel, ActorLabelEntities,
    DialogueChoiceButton, DialogueChoiceRow, DialoguePanelBodyLabel, DialoguePanelChoicesRoot,
    DialoguePanelHintLabel, DialoguePanelRoot, DialoguePanelSpeakerLabel,
    DialoguePanelTitleLabel, InteractionLockedActorTag, InteractionMenuButton,
    InteractionMenuOptionRow, InteractionMenuOptionsRoot, InteractionMenuRoot,
    InteractionMenuState, UiMouseBlocker, UiMouseBlockerName, ViewerActorFeedbackState,
    ViewerActorMotionState, ViewerCamera, ViewerCameraFollowState, ViewerCameraShakeState,
    ViewerDamageNumberState, ViewerOverlayMode, ViewerPalette, ViewerRenderConfig,
    ViewerRuntimeState, ViewerSceneKind, ViewerState, ViewerStyleProfile, ViewerUiFont,
};
use crate::ui_context_menu::{
    context_menu_border_color, context_menu_button_color, context_menu_button_node,
    context_menu_panel_color, context_menu_root_node, context_menu_text_color, ContextMenuStyle,
    ContextMenuVariant,
};

mod camera;
mod constants;
mod debug_draw;
mod fog_of_war;
mod hover_outline;
mod materials;
mod mesh_builders;
mod occlusion;
mod overlay;
mod resources;
#[cfg(test)]
mod tests;
mod types;
mod world;

pub(super) use camera::*;
pub(super) use constants::*;
pub(super) use debug_draw::*;
pub(super) use fog_of_war::*;
pub(super) use hover_outline::*;
use materials::*;
use mesh_builders::*;
use occlusion::*;
pub(super) use overlay::*;
pub(super) use resources::*;
pub(super) use types::*;
pub(super) use world::*;
