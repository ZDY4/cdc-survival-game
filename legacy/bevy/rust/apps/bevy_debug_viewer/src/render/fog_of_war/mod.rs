//! 战争迷雾模块门面：统一组织 mask 快照构建与后处理渲染，并保持 render 层对外入口稳定。

use super::*;

mod mask;
mod post_process;

const FOG_OF_WAR_MASK_VISIBLE: u8 = 0;
const FOG_OF_WAR_MASK_EXPLORED: u8 = 128;
const FOG_OF_WAR_MASK_UNEXPLORED: u8 = 255;
const FOG_OF_WAR_POST_PROCESS_SHADER_PATH: &str = "shaders/fog_of_war_post_process.wgsl";

pub(super) use mask::{
    build_fog_of_war_mask_image, build_fog_of_war_mask_snapshot, current_focus_actor_vision,
    update_fog_of_war_mask_image,
};
pub(crate) use post_process::{
    sync_fog_of_war_post_process_camera, tick_fog_of_war_transition, FogOfWarOverlay,
    FogOfWarPostProcessPlugin, FogOfWarPostProcessSettings, FogOfWarPostProcessTextures,
};
