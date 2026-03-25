use bevy::ecs::schedule::IntoScheduleConfigs;
use bevy::prelude::*;
use bevy::window::WindowPlugin;
use game_bevy::{
    load_character_definitions_on_startup, load_settlement_definitions_on_startup,
    spawn_characters_from_definition, CharacterDefinitionPath, CharacterSpawnRejected,
    NpcLifePlugin, SettlementDefinitionPath, SettlementSimulationPlugin, SpawnCharacterRequest,
};
use game_data::GameDataPlugin;

use crate::bootstrap::load_viewer_bootstrap;
use crate::controls::{
    handle_camera_pan, handle_interaction_menu_buttons, handle_keyboard_input, handle_mouse_input,
    handle_mouse_wheel_zoom, update_view_scale,
};
use crate::render::{
    draw_world, setup_viewer, sync_actor_labels, update_camera, update_dialogue_panel,
    update_interaction_menu,
};
use crate::simulation::{
    advance_online_npc_actions, advance_runtime_progression, collect_events, prime_viewer_state,
    refresh_interaction_prompt, sync_npc_runtime_presence, tick_runtime,
};
use crate::state::{ActorLabelEntities, ViewerRenderConfig, ViewerRuntimeState, ViewerState};

pub(crate) fn run() {
    let bootstrap = load_viewer_bootstrap()
        .unwrap_or_else(|error| panic!("failed to load bevy_debug_viewer bootstrap: {error}"));

    App::new()
        .add_plugins(ViewerAppPlugin {
            asset_dir: bootstrap.asset_dir,
        })
        .insert_resource(ClearColor(Color::srgb(0.04, 0.05, 0.07)))
        .insert_resource(ViewerRuntimeState {
            runtime: bootstrap.runtime,
            recent_events: Vec::new(),
            ai_snapshot: Default::default(),
        })
        .insert_resource(ActorLabelEntities::default())
        .insert_resource(ViewerRenderConfig::default())
        .insert_resource(ViewerState::default())
        .run();
}

struct ViewerAppPlugin {
    asset_dir: std::path::PathBuf,
}

impl Plugin for ViewerAppPlugin {
    fn build(&self, app: &mut App) {
        app.add_plugins(
            DefaultPlugins
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
        .insert_resource(CharacterDefinitionPath::default())
        .insert_resource(SettlementDefinitionPath::default())
        .add_plugins((GameDataPlugin, SettlementSimulationPlugin, NpcLifePlugin))
        .add_message::<SpawnCharacterRequest>()
        .add_message::<CharacterSpawnRejected>()
        .add_systems(
            Startup,
            (
                load_character_definitions_on_startup,
                load_settlement_definitions_on_startup,
                queue_life_debug_spawns,
                setup_viewer,
                prime_viewer_state,
            )
                .chain(),
        )
        .add_systems(
            Update,
            (
                spawn_characters_from_definition,
                sync_npc_runtime_presence,
                advance_online_npc_actions,
                sync_ai_snapshot,
                handle_keyboard_input,
                handle_mouse_wheel_zoom,
                update_view_scale,
                handle_camera_pan,
                update_camera,
                handle_mouse_input,
                handle_interaction_menu_buttons,
                tick_runtime,
                advance_runtime_progression,
                collect_events,
                refresh_interaction_prompt,
                sync_actor_labels,
                crate::hud::update_hud,
                update_interaction_menu,
                update_dialogue_panel,
                draw_world,
            )
                .chain(),
        );
    }
}

fn queue_life_debug_spawns(
    definitions: Res<game_bevy::CharacterDefinitions>,
    mut requests: MessageWriter<SpawnCharacterRequest>,
) {
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
