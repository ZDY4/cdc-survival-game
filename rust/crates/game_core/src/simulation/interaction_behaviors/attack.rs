use game_data::{
    ActorId, ActorSide, InteractionExecutionResult, InteractionOptionDefinition,
    InteractionOptionKind, InteractionTargetId,
};
use tracing::info;

use crate::simulation::{
    interaction_behaviors::{default_allows_primary, InteractionBehavior, InteractionExecutionContext},
    Simulation, SimulationEvent,
};

const KINDS: &[InteractionOptionKind] = &[InteractionOptionKind::Attack];

pub(crate) const BEHAVIOR: InteractionBehavior = InteractionBehavior {
    kinds: KINDS,
    resolve_view: resolve_attack_option_view,
    execute: execute_attack_interaction,
    allows_primary: default_allows_primary,
};

pub(crate) fn default_actor_option(
    simulation: &Simulation,
    actor_id: ActorId,
    side: ActorSide,
) -> Option<InteractionOptionDefinition> {
    if actor_id == ActorId(0) {
        return None;
    }

    let mut attack = InteractionOptionDefinition {
        kind: InteractionOptionKind::Attack,
        dangerous: side != ActorSide::Hostile,
        priority: if side == ActorSide::Hostile {
            1000
        } else {
            -100
        },
        interaction_distance: simulation
            .actor_attack_ranges
            .get(&actor_id)
            .copied()
            .unwrap_or(1.2)
            .max(1.0),
        ..InteractionOptionDefinition::default()
    };
    attack.ensure_defaults();
    Some(attack)
}

fn resolve_attack_option_view(
    simulation: &Simulation,
    actor_id: ActorId,
    target_id: &InteractionTargetId,
    option: &mut InteractionOptionDefinition,
) {
    option.interaction_distance = simulation.attack_interaction_distance(actor_id);
    if matches!(target_id, InteractionTargetId::Actor(target_actor) if simulation.get_actor_side(*target_actor) == Some(ActorSide::Hostile))
    {
        option.dangerous = false;
        option.priority = option.priority.max(1000);
    }
}

fn execute_attack_interaction(
    simulation: &mut Simulation,
    context: InteractionExecutionContext,
) -> InteractionExecutionResult {
    let InteractionTargetId::Actor(target_actor) = context.target_id else {
        return simulation.failed_interaction_execution(
            context.actor_id,
            context.prompt,
            context.option.id,
            "attack_target_invalid",
            false,
        );
    };
    let action = simulation.perform_attack(context.actor_id, target_actor);
    if !action.success {
        return simulation.failed_interaction_action(
            context.actor_id,
            InteractionTargetId::Actor(target_actor),
            context.prompt,
            context.option.id,
            action,
        );
    }
    simulation
        .events
        .push(SimulationEvent::InteractionSucceeded {
            actor_id: context.actor_id,
            target_id: InteractionTargetId::Actor(target_actor),
            option_id: context.option.id.clone(),
        });
    info!(
        "core.interaction.succeeded actor={:?} target={:?} option_id={}",
        context.actor_id,
        InteractionTargetId::Actor(target_actor),
        context.option.id.as_str()
    );
    InteractionExecutionResult {
        success: true,
        prompt: Some(context.prompt),
        action_result: Some(action),
        ..InteractionExecutionResult::default()
    }
}
