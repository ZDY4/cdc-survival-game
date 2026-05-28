//! Runtime interaction option filters.

use game_data::{ActorId, InteractionOptionDefinition, InteractionOptionKind, InteractionTargetId};

use super::Simulation;

pub(crate) struct InteractionOptionFilterContext<'a> {
    pub simulation: &'a Simulation,
    // 预留给依赖发起者状态的过滤规则；当前首条规则只读取目标角色状态。
    #[allow(dead_code)]
    pub actor_id: ActorId,
    pub target_id: &'a InteractionTargetId,
}

pub(crate) fn option_is_available(
    context: &InteractionOptionFilterContext<'_>,
    option: &InteractionOptionDefinition,
) -> bool {
    !blocks_talk_with_combat_actor(context, option)
}

fn blocks_talk_with_combat_actor(
    context: &InteractionOptionFilterContext<'_>,
    option: &InteractionOptionDefinition,
) -> bool {
    if option.kind != InteractionOptionKind::Talk {
        return false;
    }

    // 只禁止和已经处于战斗状态的目标角色新建对话，不影响地图物件或已打开对话。
    let InteractionTargetId::Actor(target_actor) = context.target_id else {
        return false;
    };

    context
        .simulation
        .actors
        .get(*target_actor)
        .is_some_and(|actor| actor.in_combat)
}
