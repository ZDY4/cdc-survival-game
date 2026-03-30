use std::collections::HashMap;
use std::time::Instant;

use bevy::prelude::*;

use crate::game_ui::{GameContentRefs, GameUiViewState};
use crate::state::{
    ActorLabelEntities, GameUiRoot, ViewerActorFeedbackState, ViewerActorMotionState, ViewerCamera,
    ViewerPalette, ViewerRenderConfig, ViewerRuntimeState, ViewerState, ViewerStyleProfile,
    ViewerUiFont,
};

const SYSTEM_TIMING_SMOOTHING_ALPHA: f64 = 0.18;

#[derive(Debug, Clone, Copy, PartialEq)]
pub(crate) struct ViewerSystemTimingEntry {
    pub name: &'static str,
    pub smoothed_ms: f64,
    pub last_ms: f64,
    pub peak_ms: f64,
}

#[derive(Debug, Clone, Copy, Default)]
struct ViewerSystemTimingStat {
    sample_count: u64,
    smoothed_ms: f64,
    last_ms: f64,
    peak_ms: f64,
}

#[derive(Resource, Debug, Default)]
pub(crate) struct ViewerSystemProfilerState {
    stats: HashMap<&'static str, ViewerSystemTimingStat>,
}

impl ViewerSystemProfilerState {
    pub(crate) fn record_sample(&mut self, name: &'static str, elapsed_ms: f64) {
        let stat = self.stats.entry(name).or_default();
        stat.sample_count += 1;
        stat.last_ms = elapsed_ms;
        stat.peak_ms = stat.peak_ms.max(elapsed_ms);
        stat.smoothed_ms = if stat.sample_count == 1 {
            elapsed_ms
        } else {
            stat.smoothed_ms * (1.0 - SYSTEM_TIMING_SMOOTHING_ALPHA)
                + elapsed_ms * SYSTEM_TIMING_SMOOTHING_ALPHA
        };
    }

    pub(crate) fn top_entries(&self, limit: usize) -> Vec<ViewerSystemTimingEntry> {
        let mut entries: Vec<_> = self
            .stats
            .iter()
            .map(|(name, stat)| ViewerSystemTimingEntry {
                name,
                smoothed_ms: stat.smoothed_ms,
                last_ms: stat.last_ms,
                peak_ms: stat.peak_ms,
            })
            .collect();
        entries.sort_by(|left, right| right.smoothed_ms.total_cmp(&left.smoothed_ms));
        entries.truncate(limit);
        entries
    }

    pub(crate) fn tracked_total_smoothed_ms(&self) -> f64 {
        self.stats.values().map(|stat| stat.smoothed_ms).sum()
    }
}

fn elapsed_ms(start: Instant) -> f64 {
    start.elapsed().as_secs_f64() * 1000.0
}

pub(crate) fn profiled_tick_runtime(
    runtime_state: ResMut<ViewerRuntimeState>,
    viewer_state: Res<ViewerState>,
    mut profiler: ResMut<ViewerSystemProfilerState>,
) {
    let start = Instant::now();
    crate::simulation::tick_runtime(runtime_state, viewer_state);
    profiler.record_sample("tick_runtime", elapsed_ms(start));
}

pub(crate) fn profiled_advance_runtime_progression(
    time: Res<Time>,
    runtime_state: ResMut<ViewerRuntimeState>,
    viewer_state: ResMut<ViewerState>,
    mut profiler: ResMut<ViewerSystemProfilerState>,
) {
    let start = Instant::now();
    crate::simulation::advance_runtime_progression(time, runtime_state, viewer_state);
    profiler.record_sample("advance_runtime_progression", elapsed_ms(start));
}

#[allow(clippy::too_many_arguments)]
pub(crate) fn profiled_sync_world_visuals(
    commands: Commands,
    meshes: ResMut<Assets<Mesh>>,
    materials: ResMut<Assets<StandardMaterial>>,
    ground_materials: ResMut<Assets<crate::render::GridGroundMaterial>>,
    building_wall_materials: ResMut<Assets<crate::render::BuildingWallGridMaterial>>,
    palette: Res<ViewerPalette>,
    trigger_decal_assets: Res<crate::render::TriggerDecalAssets>,
    runtime_state: Res<ViewerRuntimeState>,
    motion_state: Res<ViewerActorMotionState>,
    feedback_state: Res<ViewerActorFeedbackState>,
    viewer_state: Res<ViewerState>,
    render_config: Res<ViewerRenderConfig>,
    static_world_state: ResMut<crate::render::StaticWorldVisualState>,
    actor_visual_state: ResMut<crate::render::ActorVisualState>,
    actor_visuals: Query<(Entity, &mut Transform, &crate::render::ActorBodyVisual)>,
    mut profiler: ResMut<ViewerSystemProfilerState>,
) {
    let start = Instant::now();
    crate::render::sync_world_visuals(
        commands,
        meshes,
        materials,
        ground_materials,
        building_wall_materials,
        palette,
        trigger_decal_assets,
        runtime_state,
        motion_state,
        feedback_state,
        viewer_state,
        render_config,
        static_world_state,
        actor_visual_state,
        actor_visuals,
    );
    profiler.record_sample("sync_world_visuals", elapsed_ms(start));
}

pub(crate) fn profiled_update_occluding_world_visuals(
    runtime_state: Res<ViewerRuntimeState>,
    motion_state: Res<ViewerActorMotionState>,
    viewer_state: Res<ViewerState>,
    render_config: Res<ViewerRenderConfig>,
    camera_query: Single<&Transform, With<ViewerCamera>>,
    materials: ResMut<Assets<StandardMaterial>>,
    building_wall_materials: ResMut<Assets<crate::render::BuildingWallGridMaterial>>,
    static_world_state: ResMut<crate::render::StaticWorldVisualState>,
    mut profiler: ResMut<ViewerSystemProfilerState>,
) {
    let start = Instant::now();
    crate::render::update_occluding_world_visuals(
        runtime_state,
        motion_state,
        viewer_state,
        render_config,
        camera_query,
        materials,
        building_wall_materials,
        static_world_state,
    );
    profiler.record_sample("update_occluding_world_visuals", elapsed_ms(start));
}

pub(crate) fn profiled_sync_actor_labels(
    commands: Commands,
    runtime_state: Res<ViewerRuntimeState>,
    motion_state: Res<ViewerActorMotionState>,
    viewer_state: Res<ViewerState>,
    palette: Res<ViewerPalette>,
    render_config: Res<ViewerRenderConfig>,
    viewer_font: Res<ViewerUiFont>,
    camera_query: Single<(&Camera, &Transform), With<ViewerCamera>>,
    label_entities: ResMut<ActorLabelEntities>,
    labels: Query<(
        Entity,
        &mut Text,
        &mut Node,
        &mut TextColor,
        &mut Visibility,
        Option<&crate::state::InteractionLockedActorTag>,
        &crate::state::ActorLabel,
    )>,
    mut profiler: ResMut<ViewerSystemProfilerState>,
) {
    let start = Instant::now();
    crate::render::sync_actor_labels(
        commands,
        runtime_state,
        motion_state,
        viewer_state,
        palette,
        render_config,
        viewer_font,
        camera_query,
        label_entities,
        labels,
    );
    profiler.record_sample("sync_actor_labels", elapsed_ms(start));
}

pub(crate) fn profiled_update_game_ui(
    commands: Commands,
    root: Single<(Entity, Option<&Children>), With<GameUiRoot>>,
    palette: Res<ViewerPalette>,
    font: Res<ViewerUiFont>,
    ui: GameUiViewState,
    content: GameContentRefs,
    mut profiler: ResMut<ViewerSystemProfilerState>,
) {
    let start = Instant::now();
    crate::game_ui::update_game_ui(commands, root, palette, font, ui, content);
    profiler.record_sample("update_game_ui", elapsed_ms(start));
}

pub(crate) fn profiled_draw_world(
    time: Res<Time>,
    gizmos: Gizmos,
    palette: Res<ViewerPalette>,
    style: Res<ViewerStyleProfile>,
    runtime_state: Res<ViewerRuntimeState>,
    settlements: Option<Res<game_bevy::SettlementDefinitions>>,
    motion_state: Res<ViewerActorMotionState>,
    viewer_state: Res<ViewerState>,
    render_config: Res<ViewerRenderConfig>,
    mut profiler: ResMut<ViewerSystemProfilerState>,
) {
    let start = Instant::now();
    crate::render::draw_world(
        time,
        gizmos,
        palette,
        style,
        runtime_state,
        settlements,
        motion_state,
        viewer_state,
        render_config,
    );
    profiler.record_sample("draw_world", elapsed_ms(start));
}

#[cfg(test)]
mod tests {
    use super::ViewerSystemProfilerState;

    #[test]
    fn top_entries_sort_by_smoothed_cost() {
        let mut profiler = ViewerSystemProfilerState::default();
        profiler.record_sample("a", 1.0);
        profiler.record_sample("b", 3.0);
        profiler.record_sample("c", 2.0);

        let top = profiler.top_entries(2);

        assert_eq!(top.len(), 2);
        assert_eq!(top[0].name, "b");
        assert_eq!(top[1].name, "c");
    }
}
