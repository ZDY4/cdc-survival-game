use bevy_app::prelude::*;
use bevy_app::{AppExit, ScheduleRunnerPlugin, TaskPoolPlugin};
use bevy_ecs::prelude::*;
use std::time::Duration;

use game_core::GameCorePlugin;
use game_core::{
    action_result_status, create_demo_runtime, SimulationCommand, SimulationCommandResult,
    SimulationEvent, SimulationRuntime,
};
use game_data::GameDataPlugin;
use game_data::GridCoord;
use game_protocol::GameProtocolPlugin;

fn main() {
    App::new()
        .insert_resource(ServerConfig::default())
        .add_plugins(TaskPoolPlugin::default())
        .add_plugins(ScheduleRunnerPlugin::run_loop(Duration::from_millis(16)))
        .add_plugins((GameDataPlugin, GameProtocolPlugin, GameCorePlugin))
        .add_systems(Startup, startup_demo)
        .run();
}

#[derive(Resource, Debug, Clone)]
struct ServerConfig {
    tick_rate_hz: u16,
}

impl Default for ServerConfig {
    fn default() -> Self {
        Self { tick_rate_hz: 60 }
    }
}

fn startup_demo(config: Res<ServerConfig>, mut app_exit: MessageWriter<AppExit>) {
    println!(
        "bevy_server booted with headless loop at {} Hz",
        config.tick_rate_hz
    );

    let (mut runtime, handles) = create_demo_runtime();
    print_events("after registration", &mut runtime);
    println!(
        "path result: {:?}",
        runtime.submit_command(SimulationCommand::FindPath {
            actor_id: Some(handles.player),
            start: GridCoord::new(0, 0, 0),
            goal: GridCoord::new(3, 0, 2),
        })
    );

    print_action_result(
        "move actor to (0,0,1)",
        runtime.submit_command(SimulationCommand::MoveActorTo {
            actor_id: handles.player,
            goal: GridCoord::new(0, 0, 1),
        }),
    );
    print_events("after noncombat move", &mut runtime);

    runtime.submit_command(SimulationCommand::EnterCombat {
        trigger_actor: handles.player,
        target_actor: handles.hostile,
    });
    print_events("after entering combat", &mut runtime);

    print_action_result(
        "perform attack",
        runtime.submit_command(SimulationCommand::PerformAttack {
            actor_id: handles.player,
            target_actor: handles.hostile,
        }),
    );
    print_events("after combat action", &mut runtime);

    let snapshot = runtime.snapshot();

    println!(
        "final state: current_actor={:?} current_group={:?} turn_index={} friendly_ap={}",
        snapshot.turn.current_actor_id,
        snapshot.turn.current_group_id,
        snapshot.turn.current_turn_index,
        snapshot
            .actors
            .iter()
            .find(|actor| actor.actor_id == handles.friendly)
            .map(|actor| actor.ap)
            .unwrap_or(0.0)
    );

    app_exit.write(AppExit::Success);
}

fn print_action_result(label: &str, result: SimulationCommandResult) {
    if let SimulationCommandResult::Action(action) = result {
        println!("{}: {}", label, action_result_status(&action));
    } else {
        println!("{}: {:?}", label, result);
    }
}

fn print_events(label: &str, runtime: &mut SimulationRuntime) {
    println!("== {} ==", label);
    for event in runtime.drain_events() {
        match event {
            SimulationEvent::GroupRegistered { group_id, order } => {
                println!("group registered: {} -> {}", group_id, order);
            }
            SimulationEvent::ActorRegistered {
                actor_id,
                group_id,
                side,
            } => {
                println!("actor registered: {:?} group={} side={:?}", actor_id, group_id, side);
            }
            SimulationEvent::ActorTurnStarted {
                actor_id,
                group_id,
                ap,
            } => {
                println!("turn started: {:?} group={} ap={}", actor_id, group_id, ap);
            }
            SimulationEvent::ActorTurnEnded {
                actor_id,
                group_id,
                remaining_ap,
            } => {
                println!(
                    "turn ended: {:?} group={} remaining_ap={}",
                    actor_id, group_id, remaining_ap
                );
            }
            SimulationEvent::CombatStateChanged { in_combat } => {
                println!("combat state changed: {}", in_combat);
            }
            SimulationEvent::ActionRejected {
                actor_id,
                action_type,
                reason,
            } => {
                println!(
                    "action rejected: actor={:?} type={:?} reason={}",
                    actor_id, action_type, reason
                );
            }
            SimulationEvent::ActionResolved {
                actor_id,
                action_type,
                result,
            } => {
                println!(
                    "action resolved: actor={:?} type={:?} ap_before={} ap_after={} consumed={}",
                    actor_id, action_type, result.ap_before, result.ap_after, result.consumed
                );
            }
            SimulationEvent::WorldCycleCompleted => {
                println!("world cycle completed");
            }
            SimulationEvent::PathComputed {
                actor_id,
                path_length,
            } => {
                println!("path computed: actor={:?} length={}", actor_id, path_length);
            }
            SimulationEvent::ActorUnregistered { actor_id } => {
                println!("actor unregistered: {:?}", actor_id);
            }
        }
    }
}
