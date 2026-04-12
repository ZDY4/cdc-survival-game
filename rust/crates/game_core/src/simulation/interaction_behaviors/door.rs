use game_data::{
    ActorId, InteractionExecutionResult, InteractionOptionDefinition, InteractionOptionKind,
    InteractionTargetId, ResolvedInteractionOption,
};
use tracing::info;

use crate::building::GeneratedDoorDebugState;
use crate::simulation::{
    interaction_behaviors::{default_resolve_view, InteractionBehavior, InteractionExecutionContext},
    Simulation, SimulationEvent,
};

const KINDS: &[InteractionOptionKind] = &[
    InteractionOptionKind::OpenDoor,
    InteractionOptionKind::CloseDoor,
    InteractionOptionKind::UnlockDoor,
    InteractionOptionKind::PickLockDoor,
];

pub(crate) const BEHAVIOR: InteractionBehavior = InteractionBehavior {
    kinds: KINDS,
    resolve_view: default_resolve_view,
    execute: execute_door_interaction,
    allows_primary: allows_primary_door_option,
};

pub(crate) fn generated_door_interaction_options(
    door: &GeneratedDoorDebugState,
) -> Vec<InteractionOptionDefinition> {
    let kinds = if door.is_locked {
        vec![
            InteractionOptionKind::UnlockDoor,
            InteractionOptionKind::PickLockDoor,
        ]
    } else if door.is_open {
        vec![InteractionOptionKind::CloseDoor]
    } else {
        vec![InteractionOptionKind::OpenDoor]
    };

    kinds
        .into_iter()
        .map(|kind| InteractionOptionDefinition {
            kind,
            ..InteractionOptionDefinition::default()
        })
        .collect()
}

fn allows_primary_door_option(
    _simulation: &Simulation,
    _actor_id: ActorId,
    _target_id: &InteractionTargetId,
    option: &ResolvedInteractionOption,
    _definition: &InteractionOptionDefinition,
) -> bool {
    matches!(
        option.kind,
        InteractionOptionKind::OpenDoor | InteractionOptionKind::CloseDoor
    )
}

fn execute_door_interaction(
    simulation: &mut Simulation,
    context: InteractionExecutionContext,
) -> InteractionExecutionResult {
    match context.option.kind {
        InteractionOptionKind::OpenDoor | InteractionOptionKind::CloseDoor => {
            execute_generated_door_toggle(simulation, context)
        }
        InteractionOptionKind::UnlockDoor | InteractionOptionKind::PickLockDoor => simulation
            .failed_interaction_execution(
                context.actor_id,
                context.prompt,
                context.option.id,
                "door_interaction_not_implemented",
                false,
            ),
        other => panic!("unsupported door interaction kind {other:?}"),
    }
}

fn execute_generated_door_toggle(
    simulation: &mut Simulation,
    context: InteractionExecutionContext,
) -> InteractionExecutionResult {
    let InteractionTargetId::MapObject(ref object_id) = context.target_id else {
        return simulation.failed_interaction_execution(
            context.actor_id,
            context.prompt,
            context.option.id,
            "door_target_invalid",
            false,
        );
    };
    let Some(door) = simulation
        .grid_world
        .generated_door_by_object_id(object_id)
        .cloned()
    else {
        return simulation.failed_interaction_execution(
            context.actor_id,
            context.prompt,
            context.option.id,
            "generated_door_missing",
            false,
        );
    };
    if context.option.kind == InteractionOptionKind::OpenDoor && door.is_locked {
        return simulation.failed_interaction_execution(
            context.actor_id,
            context.prompt,
            context.option.id,
            "door_locked",
            false,
        );
    }
    let next_open = context.option.kind == InteractionOptionKind::OpenDoor;
    if door.is_open == next_open {
        return simulation.failed_interaction_execution(
            context.actor_id,
            context.prompt,
            context.option.id,
            if next_open {
                "door_already_open"
            } else {
                "door_already_closed"
            },
            false,
        );
    }

    let action = simulation.perform_interact(context.actor_id);
    if !action.success {
        return simulation.failed_interaction_action(
            context.actor_id,
            context.target_id,
            context.prompt,
            context.option.id,
            action,
        );
    }

    simulation
        .grid_world
        .set_generated_door_state(&door.door_id, next_open, door.is_locked);
    simulation
        .events
        .push(SimulationEvent::InteractionSucceeded {
            actor_id: context.actor_id,
            target_id: context.target_id.clone(),
            option_id: context.option.id.clone(),
        });
    info!(
        "core.interaction.generated_door actor={:?} target={:?} option_id={} open={}",
        context.actor_id,
        context.target_id,
        context.option.id.as_str(),
        next_open
    );
    InteractionExecutionResult {
        success: true,
        prompt: Some(context.prompt),
        action_result: Some(action),
        ..InteractionExecutionResult::default()
    }
}
