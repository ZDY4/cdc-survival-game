//! 交互行为注册层：按交互类型挂接具体行为模块，集中提供分发入口。

use super::*;

pub(crate) mod attack;
pub(crate) mod door;
pub(crate) mod pickup;
pub(crate) mod scene_transition;
pub(crate) mod talk;
pub(crate) mod wait;

#[derive(Debug, Clone)]
pub(crate) struct InteractionExecutionContext {
    /// 当前发起交互的 actor。
    pub actor_id: ActorId,
    /// 交互目标语义 ID。
    pub target_id: InteractionTargetId,
    /// 执行前构建出的完整 prompt。
    pub prompt: InteractionPrompt,
    /// 当前被触发的已解析选项。
    pub option: ResolvedInteractionOption,
    /// 当前选项的原始定义。
    pub option_definition: InteractionOptionDefinition,
}

#[derive(Clone, Copy)]
pub(crate) struct InteractionBehavior {
    /// 该行为模块负责的交互 kind 集合。
    pub kinds: &'static [InteractionOptionKind],
    /// 允许在 prompt 展示前修正视图文案和危险度等显示信息。
    pub resolve_view:
        fn(&Simulation, ActorId, &InteractionTargetId, &mut InteractionOptionDefinition),
    /// 真正执行该类交互。
    pub execute: fn(&mut Simulation, InteractionExecutionContext) -> InteractionExecutionResult,
    /// 判定该选项能否作为主交互入口。
    pub allows_primary: fn(
        &Simulation,
        ActorId,
        &InteractionTargetId,
        &ResolvedInteractionOption,
        &InteractionOptionDefinition,
    ) -> bool,
}

impl InteractionBehavior {
    fn handles_kind(&self, kind: InteractionOptionKind) -> bool {
        self.kinds.contains(&kind)
    }
}

const fn default_behavior(
    kinds: &'static [InteractionOptionKind],
    execute: fn(&mut Simulation, InteractionExecutionContext) -> InteractionExecutionResult,
) -> InteractionBehavior {
    InteractionBehavior {
        kinds,
        resolve_view: default_resolve_view,
        execute,
        allows_primary: default_allows_primary,
    }
}

fn default_resolve_view(
    _simulation: &Simulation,
    _actor_id: ActorId,
    _target_id: &InteractionTargetId,
    _option: &mut InteractionOptionDefinition,
) {
}

fn default_allows_primary(
    _simulation: &Simulation,
    _actor_id: ActorId,
    _target_id: &InteractionTargetId,
    _option: &ResolvedInteractionOption,
    _definition: &InteractionOptionDefinition,
) -> bool {
    true
}

static BEHAVIORS: [InteractionBehavior; 6] = [
    wait::BEHAVIOR,
    talk::BEHAVIOR,
    attack::BEHAVIOR,
    pickup::BEHAVIOR,
    door::BEHAVIOR,
    scene_transition::BEHAVIOR,
];

pub(crate) fn all_interaction_behaviors() -> &'static [InteractionBehavior] {
    &BEHAVIORS
}

pub(crate) fn behavior_for_kind(kind: InteractionOptionKind) -> &'static InteractionBehavior {
    all_interaction_behaviors()
        .iter()
        .find(|behavior| behavior.handles_kind(kind))
        .unwrap_or_else(|| panic!("missing interaction behavior for {kind:?}"))
}

pub(crate) fn build_self_actor_options() -> Vec<InteractionOptionDefinition> {
    wait::self_actor_options()
}

pub(crate) fn build_default_actor_options(
    simulation: &Simulation,
    actor_id: ActorId,
    side: ActorSide,
    definition_id: Option<&CharacterId>,
) -> Vec<InteractionOptionDefinition> {
    let mut options = Vec::new();
    if let Some(option) = talk::default_actor_option(definition_id, side) {
        options.push(option);
    }
    if let Some(option) = attack::default_actor_option(simulation, actor_id, side) {
        options.push(option);
    }
    options
}

pub(crate) fn resolve_map_object_options(
    object: &MapObjectDefinition,
) -> Vec<InteractionOptionDefinition> {
    match object.kind {
        MapObjectKind::Pickup => pickup::map_object_options(object),
        MapObjectKind::Interactive => object
            .props
            .interactive
            .as_ref()
            .map(|interactive| interactive.resolved_options())
            .unwrap_or_default(),
        MapObjectKind::Building | MapObjectKind::Trigger | MapObjectKind::AiSpawn => Vec::new(),
    }
}

pub(crate) fn resolve_map_trigger_options(
    object: &MapObjectDefinition,
) -> Vec<InteractionOptionDefinition> {
    if object.kind != MapObjectKind::Trigger {
        return Vec::new();
    }
    object
        .props
        .trigger
        .as_ref()
        .map(|trigger| trigger.resolved_options())
        .unwrap_or_default()
}

pub(crate) fn resolve_interaction_option_view(
    simulation: &Simulation,
    actor_id: ActorId,
    target_id: &InteractionTargetId,
    mut option: InteractionOptionDefinition,
) -> ResolvedInteractionOption {
    option.ensure_defaults();
    (behavior_for_kind(option.kind).resolve_view)(simulation, actor_id, target_id, &mut option);
    ResolvedInteractionOption {
        id: option.id,
        display_name: option.display_name,
        description: option.description,
        priority: option.priority,
        dangerous: option.dangerous,
        requires_proximity: option.requires_proximity,
        interaction_distance: option.interaction_distance,
        kind: option.kind,
    }
}

pub(crate) fn allows_primary_option(
    simulation: &Simulation,
    actor_id: ActorId,
    target_id: &InteractionTargetId,
    option: &ResolvedInteractionOption,
    definition: &InteractionOptionDefinition,
) -> bool {
    (behavior_for_kind(option.kind).allows_primary)(
        simulation, actor_id, target_id, option, definition,
    )
}

pub(crate) fn execute_behavior(
    simulation: &mut Simulation,
    context: InteractionExecutionContext,
) -> InteractionExecutionResult {
    (behavior_for_kind(context.option.kind).execute)(simulation, context)
}

pub(crate) const fn build_default_behavior(
    kinds: &'static [InteractionOptionKind],
    execute: fn(&mut Simulation, InteractionExecutionContext) -> InteractionExecutionResult,
) -> InteractionBehavior {
    default_behavior(kinds, execute)
}

#[cfg(test)]
mod tests {
    use super::{all_interaction_behaviors, behavior_for_kind};
    use game_data::{all_interaction_kind_specs, InteractionOptionKind};

    #[test]
    fn behavior_registry_covers_every_interaction_kind_once() {
        let registered_kinds: Vec<InteractionOptionKind> = all_interaction_behaviors()
            .iter()
            .flat_map(|behavior| behavior.kinds.iter().copied())
            .collect();
        assert_eq!(registered_kinds.len(), all_interaction_kind_specs().len());

        for spec in all_interaction_kind_specs() {
            let occurrences = registered_kinds
                .iter()
                .filter(|kind| **kind == spec.kind)
                .count();
            assert_eq!(
                occurrences, 1,
                "unexpected behavior count for {:?}",
                spec.kind
            );
            assert!(behavior_for_kind(spec.kind).kinds.contains(&spec.kind));
        }
    }
}
