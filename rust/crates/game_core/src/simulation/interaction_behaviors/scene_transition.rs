use game_data::{
    ActorId, InteractionContextSnapshot, InteractionExecutionResult, InteractionOptionDefinition,
    InteractionOptionKind, InteractionTargetId, MapObjectKind,
};
use tracing::info;

use crate::simulation::{
    interaction_behaviors::{default_allows_primary, InteractionBehavior, InteractionExecutionContext},
    Simulation, SimulationEvent,
};

const KINDS: &[InteractionOptionKind] = &[
    InteractionOptionKind::EnterSubscene,
    InteractionOptionKind::EnterOverworld,
    InteractionOptionKind::ExitToOutdoor,
    InteractionOptionKind::EnterOutdoorLocation,
];

pub(crate) const BEHAVIOR: InteractionBehavior = InteractionBehavior {
    kinds: KINDS,
    resolve_view: resolve_scene_transition_option_view,
    execute: execute_scene_transition_interaction,
    allows_primary: default_allows_primary,
};

fn resolve_scene_transition_option_view(
    simulation: &Simulation,
    _actor_id: ActorId,
    target_id: &InteractionTargetId,
    option: &mut InteractionOptionDefinition,
) {
    if !is_scene_transition_trigger_target(simulation, target_id) {
        return;
    }

    // Scene-transition triggers should only fire after the actor actually steps
    // onto one of the trigger's covered cells, not from an adjacent tile.
    option.interaction_distance = 0.0;
}

fn execute_scene_transition_interaction(
    simulation: &mut Simulation,
    context: InteractionExecutionContext,
) -> InteractionExecutionResult {
    let action = simulation.perform_interact(context.actor_id);
    if !action.success {
        return simulation.failed_interaction_action(
            context.actor_id,
            context.target_id.clone(),
            context.prompt,
            context.option.id.clone(),
            action,
        );
    }
    let context_snapshot =
        match execute_transition(simulation, context.actor_id, &context.option_definition) {
            Ok(snapshot) => snapshot,
            Err(reason) => {
                return simulation.failed_interaction_execution(
                    context.actor_id,
                    context.prompt,
                    context.option.id.clone(),
                    &reason,
                    true,
                );
            }
        };
    simulation
        .events
        .push(SimulationEvent::InteractionSucceeded {
            actor_id: context.actor_id,
            target_id: context.target_id.clone(),
            option_id: context.option.id.clone(),
        });
    info!(
        "core.interaction.scene_transition actor={:?} target={:?} option_id={} mode={:?}",
        context.actor_id,
        context.target_id,
        context.option.id.as_str(),
        context_snapshot.world_mode
    );
    InteractionExecutionResult {
        success: true,
        prompt: Some(context.prompt),
        action_result: Some(action),
        context_snapshot: Some(context_snapshot),
        ..InteractionExecutionResult::default()
    }
}

fn execute_transition(
    simulation: &mut Simulation,
    actor_id: ActorId,
    option: &InteractionOptionDefinition,
) -> Result<InteractionContextSnapshot, String> {
    let target_id = resolve_scene_target_id(option);
    let entry_point_override =
        (!option.return_spawn_id.trim().is_empty()).then_some(option.return_spawn_id.as_str());

    match option.kind {
        InteractionOptionKind::EnterSubscene
        | InteractionOptionKind::ExitToOutdoor
        | InteractionOptionKind::EnterOutdoorLocation => {
            simulation.enter_location(actor_id, &target_id, entry_point_override)?;
        }
        InteractionOptionKind::EnterOverworld => {
            simulation.return_to_overworld(actor_id)?;
        }
        other => panic!("unsupported scene transition interaction kind {other:?}"),
    }

    Ok(simulation.current_interaction_context())
}

pub(crate) fn resolve_scene_target_id(option: &InteractionOptionDefinition) -> String {
    if !option.target_id.trim().is_empty() {
        option.target_id.clone()
    } else {
        option.target_map_id.clone()
    }
}

fn is_scene_transition_trigger_target(
    simulation: &Simulation,
    target_id: &InteractionTargetId,
) -> bool {
    let InteractionTargetId::MapObject(object_id) = target_id else {
        return false;
    };
    simulation
        .grid_world()
        .map_object(object_id)
        .is_some_and(|object| object.kind == MapObjectKind::Trigger)
}
