use super::*;

const KINDS: &[InteractionOptionKind] = &[InteractionOptionKind::Pickup];

pub(crate) const BEHAVIOR: InteractionBehavior =
    build_default_behavior(KINDS, execute_pickup_interaction);

pub(crate) fn map_object_options(object: &MapObjectDefinition) -> Vec<InteractionOptionDefinition> {
    object
        .props
        .pickup
        .as_ref()
        .map(|pickup| {
            vec![InteractionOptionDefinition {
                kind: InteractionOptionKind::Pickup,
                item_id: pickup.item_id.clone(),
                min_count: pickup.min_count.max(1),
                max_count: pickup.max_count.max(pickup.min_count.max(1)),
                ..InteractionOptionDefinition::default()
            }]
        })
        .unwrap_or_default()
}

fn execute_pickup_interaction(
    simulation: &mut Simulation,
    context: InteractionExecutionContext,
) -> InteractionExecutionResult {
    let InteractionTargetId::MapObject(ref object_id) = context.target_id else {
        return simulation.failed_interaction_execution(
            context.actor_id,
            context.prompt,
            context.option.id,
            "pickup_target_invalid",
            false,
        );
    };
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

    let count = context
        .option_definition
        .max_count
        .max(context.option_definition.min_count)
        .max(1);
    let pickup_item_id = match context.option_definition.item_id.trim().parse::<u32>() {
        Ok(item_id) => item_id,
        Err(_) => {
            return simulation.failed_interaction_execution(
                context.actor_id,
                context.prompt,
                context.option.id,
                "pickup_item_invalid",
                true,
            );
        }
    };
    simulation.grid_world.remove_map_object(object_id);
    simulation.economy.ensure_actor(context.actor_id);
    if let Err(error) =
        simulation
            .economy
            .add_item_unchecked(context.actor_id, pickup_item_id, count)
    {
        let error_message = error.to_string();
        return simulation.failed_interaction_execution(
            context.actor_id,
            context.prompt,
            context.option.id,
            &error_message,
            true,
        );
    }
    simulation.advance_collect_quest_progress(context.actor_id, pickup_item_id, count);
    simulation.events.push(SimulationEvent::PickupGranted {
        actor_id: context.actor_id,
        target_id: context.target_id.clone(),
        item_id: context.option_definition.item_id.clone(),
        count,
    });
    simulation
        .events
        .push(SimulationEvent::InteractionSucceeded {
            actor_id: context.actor_id,
            target_id: context.target_id.clone(),
            option_id: context.option.id.clone(),
        });
    info!(
        "core.interaction.pickup_succeeded actor={:?} target={:?} option_id={} item_id={} count={}",
        context.actor_id,
        context.target_id,
        context.option.id.as_str(),
        context.option_definition.item_id,
        count
    );
    InteractionExecutionResult {
        success: true,
        prompt: Some(context.prompt),
        action_result: Some(action),
        consumed_target: true,
        ..InteractionExecutionResult::default()
    }
}
