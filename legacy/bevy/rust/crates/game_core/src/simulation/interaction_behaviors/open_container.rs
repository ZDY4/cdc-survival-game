use game_data::{InteractionExecutionResult, InteractionOptionKind, InteractionTargetId};
use tracing::info;

use crate::simulation::{
    interaction_behaviors::{
        build_default_behavior, InteractionBehavior, InteractionExecutionContext,
    },
    Simulation, SimulationEvent,
};

const KINDS: &[InteractionOptionKind] = &[InteractionOptionKind::OpenContainer];

pub(crate) const BEHAVIOR: InteractionBehavior =
    build_default_behavior(KINDS, execute_open_container_interaction);

fn execute_open_container_interaction(
    simulation: &mut Simulation,
    context: InteractionExecutionContext,
) -> InteractionExecutionResult {
    let InteractionTargetId::MapObject(ref object_id) = context.target_id else {
        return simulation.failed_interaction_execution(
            context.actor_id,
            context.prompt,
            context.option.id,
            "container_target_invalid",
            false,
        );
    };

    let Some(object) = simulation.grid_world.map_object(object_id).cloned() else {
        return simulation.failed_interaction_execution(
            context.actor_id,
            context.prompt,
            context.option.id,
            "container_target_missing",
            false,
        );
    };
    if object.props.container.is_none() {
        return simulation.failed_interaction_execution(
            context.actor_id,
            context.prompt,
            context.option.id,
            "container_missing",
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

    let Some(container_id) = simulation.ensure_container_for_map_object(&object) else {
        return simulation.failed_interaction_execution(
            context.actor_id,
            context.prompt,
            context.option.id,
            "container_runtime_missing",
            false,
        );
    };

    simulation
        .events
        .push(SimulationEvent::InteractionSucceeded {
            actor_id: context.actor_id,
            target_id: context.target_id.clone(),
            option_id: context.option.id.clone(),
        });
    simulation.events.push(SimulationEvent::ContainerOpened {
        actor_id: context.actor_id,
        target_id: context.target_id.clone(),
        container_id: container_id.clone(),
    });
    info!(
        "core.interaction.container_opened actor={:?} target={:?} option_id={} container_id={}",
        context.actor_id,
        context.target_id,
        context.option.id.as_str(),
        container_id
    );
    InteractionExecutionResult {
        success: true,
        prompt: Some(context.prompt),
        action_result: Some(action),
        ..InteractionExecutionResult::default()
    }
}
