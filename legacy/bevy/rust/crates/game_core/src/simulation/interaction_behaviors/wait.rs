use game_data::{InteractionExecutionResult, InteractionOptionDefinition, InteractionOptionKind};
use tracing::info;

use crate::simulation::{
    interaction_behaviors::{
        build_default_behavior, InteractionBehavior, InteractionExecutionContext,
    },
    Simulation, SimulationEvent,
};

const KINDS: &[InteractionOptionKind] = &[InteractionOptionKind::Wait];

pub(crate) const BEHAVIOR: InteractionBehavior =
    build_default_behavior(KINDS, execute_wait_interaction);

pub(crate) fn self_actor_options() -> Vec<InteractionOptionDefinition> {
    let mut wait = InteractionOptionDefinition {
        kind: InteractionOptionKind::Wait,
        display_name: "等待".to_string(),
        description: "结束当前回合".to_string(),
        requires_proximity: false,
        priority: 950,
        ..InteractionOptionDefinition::default()
    };
    wait.ensure_defaults();
    vec![wait]
}

fn execute_wait_interaction(
    simulation: &mut Simulation,
    context: InteractionExecutionContext,
) -> InteractionExecutionResult {
    let action = simulation.end_turn(context.actor_id);
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
        .events
        .push(SimulationEvent::InteractionSucceeded {
            actor_id: context.actor_id,
            target_id: context.target_id.clone(),
            option_id: context.option.id.clone(),
        });
    info!(
        "core.interaction.wait actor={:?} target={:?} option_id={}",
        context.actor_id,
        context.target_id,
        context.option.id.as_str()
    );
    InteractionExecutionResult {
        success: true,
        prompt: Some(context.prompt),
        action_result: Some(action),
        ..InteractionExecutionResult::default()
    }
}
