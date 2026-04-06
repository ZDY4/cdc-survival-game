use super::*;

const KINDS: &[InteractionOptionKind] = &[InteractionOptionKind::Talk];

pub(crate) const BEHAVIOR: InteractionBehavior =
    build_default_behavior(KINDS, execute_talk_interaction);

pub(crate) fn default_actor_option(
    definition_id: Option<&CharacterId>,
    side: ActorSide,
) -> Option<InteractionOptionDefinition> {
    if side == ActorSide::Hostile {
        return None;
    }

    let dialogue_id = definition_id
        .map(CharacterId::as_str)
        .unwrap_or_default()
        .to_string();
    let mut talk = InteractionOptionDefinition {
        kind: InteractionOptionKind::Talk,
        dialogue_id,
        priority: 800,
        ..InteractionOptionDefinition::default()
    };
    talk.ensure_defaults();
    Some(talk)
}

fn execute_talk_interaction(
    simulation: &mut Simulation,
    context: InteractionExecutionContext,
) -> InteractionExecutionResult {
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

    let dialogue_id =
        resolve_dialogue_id(simulation, &context.target_id, &context.option_definition)
            .filter(|value| !value.trim().is_empty());
    let dialogue_state = dialogue_id.as_ref().and_then(|dialogue_id| {
        simulation.start_dialogue_session(
            context.actor_id,
            Some(context.target_id.clone()),
            dialogue_id,
        )
    });
    simulation
        .events
        .push(SimulationEvent::InteractionSucceeded {
            actor_id: context.actor_id,
            target_id: context.target_id.clone(),
            option_id: context.option.id.clone(),
        });
    info!(
        "core.interaction.dialogue_started actor={:?} target={:?} option_id={} dialogue_id={}",
        context.actor_id,
        context.target_id,
        context.option.id.as_str(),
        dialogue_id.as_deref().unwrap_or("none")
    );
    InteractionExecutionResult {
        success: true,
        prompt: Some(context.prompt),
        action_result: Some(action),
        dialogue_id,
        dialogue_state,
        ..InteractionExecutionResult::default()
    }
}

fn resolve_dialogue_id(
    simulation: &Simulation,
    target_id: &InteractionTargetId,
    option_definition: &InteractionOptionDefinition,
) -> Option<String> {
    if !option_definition.dialogue_id.trim().is_empty() {
        return Some(option_definition.dialogue_id.clone());
    }

    match target_id {
        InteractionTargetId::Actor(actor_id) => simulation
            .actors
            .get(*actor_id)
            .and_then(|actor| actor.definition_id.as_ref())
            .map(CharacterId::as_str)
            .map(str::to_string),
        InteractionTargetId::MapObject(object_id) => Some(object_id.clone()),
    }
}
