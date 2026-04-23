use bevy::diagnostic::FrameTimeDiagnosticsPlugin;
use bevy::ecs::schedule::IntoScheduleConfigs;
use bevy::log::error;
use bevy::log::LogPlugin;
use bevy::prelude::*;
use bevy::window::WindowPlugin;
use bevy_mesh_outline::MeshOutlinePlugin;
use game_bevy::world_render::WorldRenderPlugin;
use game_bevy::{
    apply_gameplay_libraries, init_runtime_logging, rust_asset_dir,
    spawn_characters_from_definition, CharacterSpawnRejected, GameUiPlugin, MapAiSpawnRuntimeState,
    NpcLifePlugin, NpcLifeUpdateSet, RuntimeContentPlugin, RuntimeLogSettings,
    SettlementSimulationPlugin, SpawnCharacterRequest,
};

use crate::bootstrap::load_viewer_bootstrap;
use crate::console::{
    handle_console_input, toggle_console, update_console_panel, ViewerConsoleState,
};
use crate::controls::{
    handle_camera_pan, handle_dialogue_choice_buttons, handle_interaction_menu_buttons,
    handle_keyboard_input, handle_mouse_input, handle_mouse_wheel_zoom,
};
use crate::game_ui::{
    apply_ui_settings_system, handle_game_ui_buttons, handle_inventory_list_mouse_wheel,
    handle_inventory_panel_pointer_input, load_ui_settings_on_startup, save_ui_settings_system,
    setup_game_ui, sync_game_ui_state, sync_inventory_list_scrollbar, tick_hotbar_cooldowns,
    update_hover_tooltip_state,
};
use crate::info_panels::update_free_observe_indicator;
use crate::picking::{sync_viewer_picking_state, ViewerPickingPlugin, ViewerPickingState};
use crate::profiling::{
    profiled_advance_runtime_progression, profiled_draw_world, profiled_sync_actor_labels,
    profiled_sync_damage_numbers, profiled_sync_world_visuals, profiled_tick_runtime,
    profiled_update_game_ui, profiled_update_occluding_world_visuals, sync_profiler_activation,
    ViewerSystemProfilerState,
};
use crate::render::{
    setup_viewer, sync_fog_of_war_post_process_camera, sync_fog_of_war_visuals,
    sync_hover_mesh_outlines, sync_stable_interaction_hover, tick_fog_of_war_transition,
    update_camera, update_dialogue_panel, update_interaction_menu, FogOfWarPostProcessPlugin,
    StableInteractionHoverState,
};
use crate::simulation::{
    advance_actor_feedback, advance_actor_motion, advance_map_ai_spawns,
    advance_online_npc_actions, advance_online_npc_combat, collect_events, prime_viewer_state,
    refresh_interaction_prompt, refresh_viewer_vision, sync_npc_runtime_presence,
    ViewerVisionTrackerState,
};
use crate::state::{
    ActorLabelEntities, UiContextMenuState, UiHoverTooltipState, UiInventoryDragState,
    UiInventoryScrollbarDragState, ViewerActorFeedbackState, ViewerActorMotionState,
    ViewerCameraFollowState, ViewerCameraShakeState, ViewerDamageNumberState, ViewerInfoPanelState,
    ViewerPalette, ViewerRenderConfig, ViewerRuntimeSavePath, ViewerRuntimeState, ViewerSceneKind,
    ViewerState, ViewerStyleProfile, ViewerUiSettings, ViewerUiSettingsPath,
};

pub(crate) fn run() {
    let log_settings = RuntimeLogSettings::new("bevy_debug_viewer").with_single_run_file();
    if let Err(error) = init_runtime_logging(&log_settings) {
        eprintln!("failed to initialize bevy_debug_viewer logging: {error}");
    }
    let (bootstrap, bootstrap_status) = match load_viewer_bootstrap() {
        Ok(bootstrap) => (bootstrap, ViewerBootstrapStatus::Ready),
        Err(error) => {
            error!("failed to load bevy_debug_viewer bootstrap: {error}");
            (
                crate::bootstrap::ViewerBootstrap {
                    runtime: game_core::SimulationRuntime::new(),
                    asset_dir: rust_asset_dir(),
                    new_game_config: game_bevy::NewGameConfig::default(),
                },
                ViewerBootstrapStatus::Failed {
                    error: error.to_string(),
                },
            )
        }
    };

    App::new()
        .add_plugins(ViewerAppPlugin {
            asset_dir: bootstrap.asset_dir,
        })
        .insert_resource(ViewerPalette::default())
        .insert_resource(ViewerStyleProfile::default())
        .insert_resource(ClearColor(ViewerPalette::default().clear_color))
        .insert_resource(ViewerRuntimeState {
            runtime: bootstrap.runtime,
            recent_events: Vec::new(),
            ai_snapshot: Default::default(),
        })
        .insert_resource(ActorLabelEntities::default())
        .insert_resource(ViewerActorMotionState::default())
        .insert_resource(ViewerActorFeedbackState::default())
        .insert_resource(ViewerCameraShakeState::default())
        .insert_resource(ViewerCameraFollowState::default())
        .insert_resource(ViewerDamageNumberState::default())
        .insert_resource(ViewerRenderConfig::default())
        .insert_resource(ViewerSceneKind::default())
        .insert_resource(ViewerPickingState::default())
        .insert_resource(StableInteractionHoverState::default())
        .insert_resource(ViewerState::default())
        .insert_resource(ViewerUiSettings::default())
        .insert_resource(ViewerUiSettingsPath::default())
        .insert_resource(ViewerRuntimeSavePath::default())
        .insert_resource(UiHoverTooltipState::default())
        .insert_resource(UiContextMenuState::default())
        .insert_resource(UiInventoryDragState::default())
        .insert_resource(UiInventoryScrollbarDragState::default())
        .insert_resource(ViewerInfoPanelState::default())
        .insert_resource(ViewerConsoleState::default())
        .insert_resource(ViewerSystemProfilerState::default())
        .insert_resource(ViewerVisionTrackerState::default())
        .insert_resource(bootstrap_status)
        .run();
}

struct ViewerAppPlugin {
    asset_dir: std::path::PathBuf,
}

#[derive(Resource, Debug, Clone, PartialEq, Eq)]
pub(crate) enum ViewerBootstrapStatus {
    Ready,
    Failed { error: String },
}

#[derive(SystemSet, Debug, Hash, PartialEq, Eq, Clone)]
enum ViewerUpdateSet {
    Picking,
    RuntimeMutations,
    EventCollection,
    Motion,
    Camera,
    Visuals,
    Hud,
}

impl Plugin for ViewerAppPlugin {
    fn build(&self, app: &mut App) {
        app.add_plugins(
            DefaultPlugins
                .build()
                .disable::<LogPlugin>()
                .set(WindowPlugin {
                    primary_window: Some(Window {
                        title: "CDC Survival Game - Bevy Debug Viewer".into(),
                        resolution: (1440, 900).into(),
                        ..default()
                    }),
                    ..default()
                })
                .set(AssetPlugin {
                    file_path: self.asset_dir.display().to_string(),
                    ..default()
                }),
        )
        .add_plugins(FrameTimeDiagnosticsPlugin::default())
        .add_plugins(MeshOutlinePlugin)
        .add_plugins(WorldRenderPlugin)
        .add_plugins(FogOfWarPostProcessPlugin)
        .add_plugins(ViewerPickingPlugin)
        .insert_resource(MapAiSpawnRuntimeState::default())
        .add_plugins((
            RuntimeContentPlugin,
            SettlementSimulationPlugin,
            NpcLifePlugin,
            GameUiPlugin,
        ))
        .configure_sets(
            Update,
            (
                NpcLifeUpdateSet::RuntimeState,
                ViewerUpdateSet::Picking,
                ViewerUpdateSet::RuntimeMutations,
                ViewerUpdateSet::EventCollection,
                ViewerUpdateSet::Motion,
                ViewerUpdateSet::Camera,
                ViewerUpdateSet::Visuals,
                ViewerUpdateSet::Hud,
            )
                .chain(),
        )
        .add_systems(
            Update,
            sync_viewer_picking_state.in_set(ViewerUpdateSet::Picking),
        )
        .add_message::<SpawnCharacterRequest>()
        .add_message::<CharacterSpawnRejected>()
        .add_systems(
            PostStartup,
            (
                configure_runtime_gameplay_content,
                queue_life_debug_spawns,
                setup_viewer,
                setup_game_ui,
                load_ui_settings_on_startup,
                prime_viewer_state,
            )
                .chain(),
        )
        .add_systems(
            Update,
            (
                apply_ui_settings_system,
                save_ui_settings_system,
                sync_game_ui_state,
                tick_hotbar_cooldowns,
            ),
        )
        // Keep runtime mutation -> event collection -> motion interpolation -> camera/visual sync
        // in one deterministic pipeline so we do not render authority positions before the
        // matching `ActorMoved` events have been converted into visual motion tracks.
        .add_systems(
            Update,
            (
                spawn_characters_from_definition,
                sync_npc_runtime_presence,
                advance_online_npc_combat,
                advance_online_npc_actions,
                advance_map_ai_spawns,
                sync_ai_snapshot,
                toggle_console,
                handle_console_input,
                handle_keyboard_input,
                handle_mouse_wheel_zoom,
                handle_inventory_list_mouse_wheel,
                handle_camera_pan,
            )
                .chain()
                .in_set(ViewerUpdateSet::RuntimeMutations),
        )
        .add_systems(
            Update,
            (
                handle_mouse_input.after(handle_game_ui_buttons),
                crate::info_panels::handle_info_panel_tab_buttons,
                handle_interaction_menu_buttons,
                handle_dialogue_choice_buttons,
                handle_inventory_panel_pointer_input,
                handle_game_ui_buttons,
                sync_profiler_activation,
                profiled_tick_runtime,
                profiled_advance_runtime_progression,
                refresh_viewer_vision,
            )
                .in_set(ViewerUpdateSet::RuntimeMutations),
        );
        app.add_systems(
            Update,
            collect_events.in_set(ViewerUpdateSet::EventCollection),
        );
        app.add_systems(
            Update,
            (
                advance_actor_motion,
                advance_actor_feedback,
                refresh_interaction_prompt,
            )
                .in_set(ViewerUpdateSet::Motion),
        );
        app.add_systems(Update, update_camera.in_set(ViewerUpdateSet::Camera));
        app.add_systems(
            Update,
            (
                profiled_sync_world_visuals,
                sync_fog_of_war_visuals,
                tick_fog_of_war_transition,
                sync_fog_of_war_post_process_camera,
                sync_stable_interaction_hover,
                profiled_sync_actor_labels,
                profiled_sync_damage_numbers,
            )
                .in_set(ViewerUpdateSet::Visuals),
        );
        app.add_systems(
            Update,
            profiled_update_occluding_world_visuals
                .after(sync_stable_interaction_hover)
                .in_set(ViewerUpdateSet::Visuals),
        );
        app.add_systems(
            Update,
            sync_hover_mesh_outlines
                .after(sync_stable_interaction_hover)
                .after(profiled_sync_world_visuals)
                .in_set(ViewerUpdateSet::Visuals),
        );
        app.add_systems(
            Update,
            (
                update_free_observe_indicator,
                crate::info_panels::update_info_panel_tab_bar,
                crate::info_panels::update_info_panel,
                crate::info_panels::update_fps_overlay,
                update_console_panel,
                update_hover_tooltip_state,
                profiled_update_game_ui,
                sync_inventory_list_scrollbar,
                update_interaction_menu,
                update_dialogue_panel,
                profiled_draw_world,
            )
                .in_set(ViewerUpdateSet::Hud),
        );
    }
}

fn queue_life_debug_spawns(
    definitions: Option<Res<game_bevy::CharacterDefinitions>>,
    mut requests: MessageWriter<SpawnCharacterRequest>,
) {
    let Some(definitions) = definitions else {
        return;
    };

    let mut next_spawn_x = 8;
    for (definition_id, definition) in definitions.0.iter() {
        if definition.life.is_none() {
            continue;
        }
        requests.write(SpawnCharacterRequest {
            definition_id: definition_id.clone(),
            grid_position: game_data::GridCoord::new(next_spawn_x, 0, 8),
        });
        next_spawn_x += 1;
    }
}

fn sync_ai_snapshot(
    mut runtime_state: ResMut<ViewerRuntimeState>,
    snapshot: Option<Res<game_bevy::SettlementDebugSnapshot>>,
) {
    if let Some(snapshot) = snapshot {
        runtime_state.ai_snapshot = snapshot.clone();
    }
}

fn configure_runtime_gameplay_content(
    mut runtime_state: ResMut<ViewerRuntimeState>,
    items: Option<Res<game_bevy::ItemDefinitions>>,
    skills: Option<Res<game_bevy::SkillDefinitions>>,
    recipes: Option<Res<game_bevy::RecipeDefinitions>>,
    quests: Option<Res<game_bevy::QuestDefinitions>>,
    shops: Option<Res<game_bevy::ShopDefinitions>>,
    overworld: Option<Res<game_bevy::OverworldDefinitions>>,
) {
    let (Some(items), Some(skills), Some(recipes), Some(quests), Some(shops), Some(overworld)) =
        (items, skills, recipes, quests, shops, overworld)
    else {
        return;
    };

    apply_gameplay_libraries(
        &mut runtime_state.runtime,
        &items,
        &skills,
        &recipes,
        &quests,
        &shops,
        &overworld,
    );
}
