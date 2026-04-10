use std::collections::HashMap;
use std::time::Instant;

use bevy::ecs::system::SystemParam;
use bevy::prelude::*;
use bevy::ui::{ComputedNode, RelativeCursorPosition, UiGlobalTransform};

use crate::game_ui::{GameContentRefs, GameUiViewState};
use crate::state::{
    ActorLabelEntities, GameUiScaffold, ViewerActorFeedbackState, ViewerActorMotionState,
    ViewerCamera, ViewerHudPage, ViewerInfoPanelState, ViewerPalette, ViewerRenderConfig,
    ViewerRuntimeState, ViewerSceneKind, ViewerState, ViewerStyleProfile, ViewerUiFont,
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
    profiling_enabled: bool,
}

impl ViewerSystemProfilerState {
    pub(crate) fn clear(&mut self) {
        self.stats.clear();
    }

    pub(crate) fn is_empty(&self) -> bool {
        self.stats.is_empty()
    }

    pub(crate) fn sync_enabled(&mut self, enabled: bool) {
        if enabled && !self.profiling_enabled {
            self.clear();
        }
        self.profiling_enabled = enabled;
    }

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

fn should_profile(info_panel_state: &ViewerInfoPanelState) -> bool {
    info_panel_state.active_page() == Some(ViewerHudPage::Performance)
}

pub(crate) fn sync_profiler_activation(
    info_panel_state: Res<ViewerInfoPanelState>,
    mut profiler: ResMut<ViewerSystemProfilerState>,
) {
    profiler.sync_enabled(should_profile(&info_panel_state));
}

#[derive(SystemParam)]
pub(crate) struct WorldVisualSyncParams<'w, 's> {
    commands: Commands<'w, 's>,
    meshes: ResMut<'w, Assets<Mesh>>,
    materials: ResMut<'w, Assets<StandardMaterial>>,
    ground_materials: ResMut<'w, Assets<crate::render::GridGroundMaterial>>,
    building_wall_materials: ResMut<'w, Assets<crate::render::BuildingWallGridMaterial>>,
    static_world_state: ResMut<'w, crate::render::StaticWorldVisualState>,
    door_visual_state: ResMut<'w, crate::render::GeneratedDoorVisualState>,
    actor_visual_state: ResMut<'w, crate::render::ActorVisualState>,
    actor_visuals: Query<
        'w,
        's,
        (
            Entity,
            &'static mut Transform,
            &'static crate::render::ActorBodyVisual,
        ),
        Without<crate::render::GeneratedDoorPivot>,
    >,
    door_pivots: Query<
        'w,
        's,
        &'static mut Transform,
        (
            With<crate::render::GeneratedDoorPivot>,
            Without<crate::render::ActorBodyVisual>,
        ),
    >,
}

pub(crate) fn profiled_tick_runtime(
    runtime_state: ResMut<ViewerRuntimeState>,
    scene_kind: Res<ViewerSceneKind>,
    viewer_state: Res<ViewerState>,
    info_panel_state: Res<ViewerInfoPanelState>,
    mut profiler: ResMut<ViewerSystemProfilerState>,
) {
    let should_record = should_profile(&info_panel_state);
    let start = should_record.then(Instant::now);
    crate::simulation::tick_runtime(runtime_state, Some(scene_kind), viewer_state);
    if let Some(start) = start {
        profiler.record_sample("tick_runtime", elapsed_ms(start));
    }
}

pub(crate) fn profiled_advance_runtime_progression(
    time: Res<Time>,
    runtime_state: ResMut<ViewerRuntimeState>,
    viewer_state: ResMut<ViewerState>,
    info_panel_state: Res<ViewerInfoPanelState>,
    mut profiler: ResMut<ViewerSystemProfilerState>,
) {
    let should_record = should_profile(&info_panel_state);
    let start = should_record.then(Instant::now);
    crate::simulation::advance_runtime_progression(time, runtime_state, viewer_state);
    if let Some(start) = start {
        profiler.record_sample("advance_runtime_progression", elapsed_ms(start));
    }
}

#[allow(clippy::too_many_arguments)]
pub(crate) fn profiled_sync_world_visuals(
    params: WorldVisualSyncParams,
    asset_server: Res<AssetServer>,
    world_tiles: Res<game_bevy::WorldTileDefinitions>,
    time: Res<Time>,
    palette: Res<ViewerPalette>,
    trigger_decal_assets: Res<crate::render::TriggerDecalAssets>,
    runtime_state: Res<ViewerRuntimeState>,
    scene_kind: Res<ViewerSceneKind>,
    motion_state: Res<ViewerActorMotionState>,
    feedback_state: Res<ViewerActorFeedbackState>,
    viewer_state: Res<ViewerState>,
    info_panel_state: Res<ViewerInfoPanelState>,
    render_config: Res<ViewerRenderConfig>,
    mut profiler: ResMut<ViewerSystemProfilerState>,
) {
    if scene_kind.is_main_menu() {
        crate::render::clear_world_visuals(
            params.commands,
            params.static_world_state,
            params.door_visual_state,
            params.actor_visual_state,
        );
        return;
    }
    let should_record = should_profile(&info_panel_state);
    let start = should_record.then(Instant::now);
    crate::render::sync_world_visuals(
        params.commands,
        params.meshes,
        params.materials,
        params.ground_materials,
        params.building_wall_materials,
        asset_server,
        world_tiles,
        time,
        palette,
        trigger_decal_assets,
        runtime_state,
        motion_state,
        feedback_state,
        viewer_state,
        render_config,
        params.static_world_state,
        params.door_visual_state,
        params.actor_visual_state,
        params.actor_visuals,
        params.door_pivots,
    );
    if let Some(start) = start {
        profiler.record_sample("sync_world_visuals", elapsed_ms(start));
    }
}

pub(crate) fn profiled_update_occluding_world_visuals(
    runtime_state: Res<ViewerRuntimeState>,
    scene_kind: Res<ViewerSceneKind>,
    motion_state: Res<ViewerActorMotionState>,
    viewer_state: Res<ViewerState>,
    stable_hover: Res<crate::render::StableInteractionHoverState>,
    info_panel_state: Res<ViewerInfoPanelState>,
    console_state: Res<crate::console::ViewerConsoleState>,
    render_config: Res<ViewerRenderConfig>,
    window: Single<&Window>,
    camera_query: Single<&Transform, With<ViewerCamera>>,
    render_params: crate::render::OcclusionRenderParams,
    static_world_state: ResMut<crate::render::StaticWorldVisualState>,
    door_visual_state: ResMut<crate::render::GeneratedDoorVisualState>,
    hover_occlusion_buffer: Local<crate::render::HoverOcclusionBuffer>,
    mut profiler: ResMut<ViewerSystemProfilerState>,
) {
    if scene_kind.is_main_menu() {
        return;
    }
    let should_record = should_profile(&info_panel_state);
    let start = should_record.then(Instant::now);
    crate::render::update_occluding_world_visuals(
        runtime_state,
        motion_state,
        viewer_state,
        stable_hover,
        scene_kind,
        console_state,
        render_config,
        window,
        camera_query,
        render_params,
        static_world_state,
        door_visual_state,
        hover_occlusion_buffer,
    );
    if let Some(start) = start {
        profiler.record_sample("update_occluding_world_visuals", elapsed_ms(start));
    }
}

pub(crate) fn profiled_sync_actor_labels(
    commands: Commands,
    runtime_state: Res<ViewerRuntimeState>,
    scene_kind: Res<ViewerSceneKind>,
    console_state: Res<crate::console::ViewerConsoleState>,
    motion_state: Res<ViewerActorMotionState>,
    viewer_state: Res<ViewerState>,
    info_panel_state: Res<ViewerInfoPanelState>,
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
    if scene_kind.is_main_menu() || console_state.is_open {
        crate::render::clear_actor_labels(commands, label_entities);
        return;
    }
    let should_record = should_profile(&info_panel_state);
    let start = should_record.then(Instant::now);
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
    if let Some(start) = start {
        profiler.record_sample("sync_actor_labels", elapsed_ms(start));
    }
}

pub(crate) fn profiled_update_game_ui(
    commands: Commands,
    scaffold: Res<GameUiScaffold>,
    ui_children: Query<Option<&Children>>,
    visibilities: Query<&mut Visibility>,
    window: Single<&Window>,
    camera_query: Single<(&Camera, &Transform), With<ViewerCamera>>,
    palette: Res<ViewerPalette>,
    font: Res<ViewerUiFont>,
    ui: GameUiViewState,
    content: GameContentRefs,
    cache: Local<crate::game_ui::GameUiRetainedCache>,
    _viewer_state: Res<ViewerState>,
    info_panel_state: Res<ViewerInfoPanelState>,
    mut profiler: ResMut<ViewerSystemProfilerState>,
) {
    let should_record = should_profile(&info_panel_state);
    let start = should_record.then(Instant::now);
    crate::game_ui::update_game_ui(
        commands,
        scaffold,
        ui_children,
        visibilities,
        window,
        camera_query,
        palette,
        font,
        ui,
        content,
        cache,
    );
    if let Some(start) = start {
        profiler.record_sample("update_game_ui", elapsed_ms(start));
    }
}

pub(crate) fn profiled_draw_world(
    time: Res<Time>,
    gizmos: Gizmos,
    palette: Res<ViewerPalette>,
    style: Res<ViewerStyleProfile>,
    runtime_state: Res<ViewerRuntimeState>,
    scene_kind: Res<ViewerSceneKind>,
    settlements: Option<Res<game_bevy::SettlementDefinitions>>,
    motion_state: Res<ViewerActorMotionState>,
    stable_hover: Res<crate::render::StableInteractionHoverState>,
    viewer_state: Res<ViewerState>,
    info_panel_state: Res<ViewerInfoPanelState>,
    render_config: Res<ViewerRenderConfig>,
    window: Single<&Window>,
    ui_blockers: Query<
        (
            &ComputedNode,
            &UiGlobalTransform,
            Option<&RelativeCursorPosition>,
            Option<&Visibility>,
            &InheritedVisibility,
            Option<&crate::state::UiMouseBlockerName>,
        ),
        With<crate::state::UiMouseBlocker>,
    >,
    mut profiler: ResMut<ViewerSystemProfilerState>,
) {
    if scene_kind.is_main_menu() {
        return;
    }
    let should_record = should_profile(&info_panel_state);
    let start = should_record.then(Instant::now);
    crate::render::draw_world(
        time,
        gizmos,
        palette,
        style,
        runtime_state,
        settlements,
        motion_state,
        stable_hover,
        viewer_state,
        render_config,
        window,
        ui_blockers,
    );
    if let Some(start) = start {
        profiler.record_sample("draw_world", elapsed_ms(start));
    }
}

pub(crate) fn profiled_sync_damage_numbers(
    commands: Commands,
    time: Res<Time>,
    scene_kind: Res<ViewerSceneKind>,
    console_state: Res<crate::console::ViewerConsoleState>,
    _viewer_state: Res<ViewerState>,
    info_panel_state: Res<ViewerInfoPanelState>,
    viewer_font: Res<ViewerUiFont>,
    camera_query: Single<(&Camera, &Transform), With<ViewerCamera>>,
    damage_numbers: ResMut<crate::state::ViewerDamageNumberState>,
    visual_state: ResMut<crate::render::DamageNumberVisualState>,
    labels: Query<(
        Entity,
        &mut Text,
        &mut TextFont,
        &mut TextColor,
        &mut Node,
        &mut Visibility,
        &crate::render::DamageNumberLabel,
    )>,
    mut profiler: ResMut<ViewerSystemProfilerState>,
) {
    if scene_kind.is_main_menu() || console_state.is_open {
        crate::render::clear_damage_numbers(commands, damage_numbers, visual_state);
        return;
    }
    let should_record = should_profile(&info_panel_state);
    let start = should_record.then(Instant::now);
    crate::render::sync_damage_numbers(
        commands,
        time,
        viewer_font,
        camera_query,
        damage_numbers,
        visual_state,
        labels,
    );
    if let Some(start) = start {
        profiler.record_sample("sync_damage_numbers", elapsed_ms(start));
    }
}

#[cfg(test)]
mod tests {
    use super::{should_profile, ViewerSystemProfilerState};
    use crate::state::{ViewerHudPage, ViewerInfoPanelState};

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

    #[test]
    fn sync_enabled_clears_samples_when_reentering_profiling() {
        let mut profiler = ViewerSystemProfilerState::default();
        profiler.sync_enabled(true);
        profiler.record_sample("draw_world", 4.0);
        assert!(!profiler.is_empty());

        profiler.sync_enabled(false);
        profiler.sync_enabled(true);

        assert!(profiler.is_empty());
        assert!(profiler.profiling_enabled);
    }

    #[test]
    fn should_profile_only_on_performance_page() {
        let mut info_panel_state = ViewerInfoPanelState::default();
        assert!(!should_profile(&info_panel_state));

        info_panel_state.toggle(ViewerHudPage::Performance);
        assert!(should_profile(&info_panel_state));
    }
}
