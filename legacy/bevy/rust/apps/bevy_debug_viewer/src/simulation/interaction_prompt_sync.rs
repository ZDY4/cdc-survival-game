//! 交互提示同步模块：根据当前聚焦目标刷新 viewer 侧 prompt 状态。

use super::*;

pub(crate) fn refresh_interaction_prompt(
    runtime_state: ResMut<ViewerRuntimeState>,
    mut viewer_state: ResMut<ViewerState>,
) {
    if viewer_state.is_free_observe() {
        viewer_state.current_prompt = None;
        return;
    }

    let snapshot = runtime_state.runtime.snapshot();
    let Some(actor_id) = viewer_state.command_actor_id(&snapshot) else {
        viewer_state.current_prompt = None;
        return;
    };
    let Some(target_id) = viewer_state.focused_target.clone() else {
        viewer_state.current_prompt = None;
        return;
    };
    viewer_state.current_prompt = runtime_state
        .runtime
        .peek_interaction_prompt(actor_id, &target_id);
}
