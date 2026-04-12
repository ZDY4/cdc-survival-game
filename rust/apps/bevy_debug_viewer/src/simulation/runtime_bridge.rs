//! 运行时桥接模块：负责 Bevy viewer 资源与 `SimulationRuntime` 之间的装配与同步。

use super::*;

pub(crate) fn command_result_status(label: &str, result: SimulationCommandResult) -> String {
    match result {
        SimulationCommandResult::Action(action) => {
            format!("{label}: {}", action_result_status(&action))
        }
        SimulationCommandResult::SkillActivation(result) => {
            let status = if result.action_result.success {
                action_result_status(&result.action_result)
            } else {
                result
                    .failure_reason
                    .clone()
                    .or(result.action_result.reason.clone())
                    .unwrap_or_else(|| "unknown".to_string())
            };
            format!("{label}: {status}")
        }
        SimulationCommandResult::Path(result) => match result {
            Ok(path) => format!("{label}: path cells={}", path.len()),
            Err(error) => format!("{label}: path error={error:?}"),
        },
        SimulationCommandResult::InteractionPrompt(prompt) => {
            format!("{label}: options={}", prompt.options.len())
        }
        SimulationCommandResult::InteractionExecution(result) => {
            format!(
                "{label}: {}",
                if result.success {
                    "ok".to_string()
                } else {
                    format!(
                        "failed {}",
                        result.reason.unwrap_or_else(|| "unknown".to_string())
                    )
                }
            )
        }
        SimulationCommandResult::DialogueState(result) => match result {
            Ok(state) => format!(
                "{label}: dialogue node={} finished={}",
                state.session.current_node_id, state.finished
            ),
            Err(error) => format!("{label}: dialogue error={error}"),
        },
        SimulationCommandResult::OverworldState(result) => match result {
            Ok(state) => format!(
                "{label}: mode={:?} location={}",
                state.world_mode,
                state.active_location_id.as_deref().unwrap_or("unknown")
            ),
            Err(error) => format!("{label}: world error={error}"),
        },
        SimulationCommandResult::LocationTransition(result) => match result {
            Ok(context) => format!(
                "{label}: entered {} map={} entry={}",
                context.location_id, context.map_id, context.entry_point_id
            ),
            Err(error) => format!("{label}: transition error={error}"),
        },
        SimulationCommandResult::InteractionContext(result) => match result {
            Ok(context) => format!(
                "{label}: mode={:?} map={:?} outdoor={:?} subscene={:?}",
                context.world_mode,
                context.current_map_id,
                context.active_outdoor_location_id,
                context.current_subscene_location_id
            ),
            Err(error) => format!("{label}: interaction context error={error}"),
        },
        SimulationCommandResult::None => format!("{label}: ok"),
    }
}

pub(crate) fn viewer_event_entry(event: SimulationEvent, turn_index: u64) -> ViewerEventEntry {
    let category = classify_event(&event);
    let text = format_event_text(event);
    ViewerEventEntry {
        category,
        turn_index,
        text,
    }
}

pub(crate) fn classify_event(event: &SimulationEvent) -> HudEventCategory {
    match event {
        SimulationEvent::ActorTurnStarted { .. }
        | SimulationEvent::ActorTurnEnded { .. }
        | SimulationEvent::CombatStateChanged { .. }
        | SimulationEvent::ActionRejected { .. }
        | SimulationEvent::ActionResolved { .. }
        | SimulationEvent::AttackResolved { .. }
        | SimulationEvent::SkillActivated { .. }
        | SimulationEvent::SkillActivationFailed { .. }
        | SimulationEvent::ActorDamaged { .. }
        | SimulationEvent::ActorDefeated { .. } => HudEventCategory::Combat,
        SimulationEvent::InteractionOptionsResolved { .. }
        | SimulationEvent::InteractionApproachPlanned { .. }
        | SimulationEvent::InteractionStarted { .. }
        | SimulationEvent::InteractionSucceeded { .. }
        | SimulationEvent::ContainerOpened { .. }
        | SimulationEvent::InteractionFailed { .. }
        | SimulationEvent::DialogueStarted { .. }
        | SimulationEvent::DialogueAdvanced { .. }
        | SimulationEvent::PickupGranted { .. }
        | SimulationEvent::RelationChanged { .. }
        | SimulationEvent::NpcActionStarted { .. }
        | SimulationEvent::NpcActionPhaseChanged { .. }
        | SimulationEvent::NpcActionCompleted { .. }
        | SimulationEvent::NpcActionFailed { .. } => HudEventCategory::Interaction,
        SimulationEvent::GroupRegistered { .. }
        | SimulationEvent::ActorRegistered { .. }
        | SimulationEvent::ActorUnregistered { .. }
        | SimulationEvent::ActorMoved { .. }
        | SimulationEvent::ActorVisionUpdated { .. }
        | SimulationEvent::WorldCycleCompleted
        | SimulationEvent::PathComputed { .. }
        | SimulationEvent::SceneTransitionRequested { .. }
        | SimulationEvent::LootDropped { .. }
        | SimulationEvent::ExperienceGranted { .. }
        | SimulationEvent::ActorLeveledUp { .. }
        | SimulationEvent::QuestStarted { .. }
        | SimulationEvent::QuestObjectiveProgressed { .. }
        | SimulationEvent::QuestCompleted { .. }
        | SimulationEvent::LocationEntered { .. }
        | SimulationEvent::ReturnedToOverworld { .. }
        | SimulationEvent::LocationUnlocked { .. } => HudEventCategory::World,
    }
}

fn format_event_text(event: SimulationEvent) -> String {
    match event {
        SimulationEvent::GroupRegistered { group_id, order } => {
            format!("group registered {group_id} -> {order}")
        }
        SimulationEvent::ActorRegistered {
            actor_id,
            group_id,
            side,
        } => format!(
            "actor {:?} registered group={} side={:?}",
            actor_id, group_id, side
        ),
        SimulationEvent::ActorUnregistered { actor_id } => {
            format!("actor {:?} unregistered", actor_id)
        }
        SimulationEvent::ActorTurnStarted {
            actor_id,
            group_id,
            ap,
        } => format!(
            "turn started {:?} group={} ap={:.1}",
            actor_id, group_id, ap
        ),
        SimulationEvent::ActorTurnEnded {
            actor_id,
            group_id,
            remaining_ap,
        } => format!(
            "turn ended {:?} group={} remaining_ap={:.1}",
            actor_id, group_id, remaining_ap
        ),
        SimulationEvent::CombatStateChanged { in_combat } => {
            format!("combat state -> {}", in_combat)
        }
        SimulationEvent::ActionRejected {
            actor_id,
            action_type,
            reason,
        } => format!(
            "action rejected actor={:?} type={:?} reason={}",
            actor_id, action_type, reason
        ),
        SimulationEvent::ActionResolved {
            actor_id,
            action_type,
            result,
        } => format!(
            "action resolved actor={:?} type={:?} ap={:.1}->{:.1} consumed={:.1}",
            actor_id, action_type, result.ap_before, result.ap_after, result.consumed
        ),
        SimulationEvent::SkillActivated {
            actor_id,
            skill_id,
            target,
            hit_actor_ids,
        } => format!(
            "skill activated actor={:?} skill={} target={:?} hits={}",
            actor_id,
            skill_id,
            target,
            hit_actor_ids.len()
        ),
        SimulationEvent::AttackResolved {
            actor_id,
            target_actor,
            outcome,
        } => format!(
            "attack resolved actor={:?} target={:?} kind={:?} damage={}",
            actor_id, target_actor, outcome.hit_kind, outcome.damage
        ),
        SimulationEvent::SkillActivationFailed {
            actor_id,
            skill_id,
            reason,
        } => format!(
            "skill failed actor={:?} skill={} reason={}",
            actor_id, skill_id, reason
        ),
        SimulationEvent::WorldCycleCompleted => "world cycle completed".to_string(),
        SimulationEvent::NpcActionStarted {
            actor_id,
            action,
            phase,
        } => format!(
            "npc action started actor={:?} action={:?} phase={:?}",
            actor_id, action, phase
        ),
        SimulationEvent::NpcActionPhaseChanged {
            actor_id,
            action,
            phase,
        } => format!(
            "npc action phase actor={:?} action={:?} phase={:?}",
            actor_id, action, phase
        ),
        SimulationEvent::NpcActionCompleted { actor_id, action } => format!(
            "npc action completed actor={:?} action={:?}",
            actor_id, action
        ),
        SimulationEvent::NpcActionFailed {
            actor_id,
            action,
            reason,
        } => format!(
            "npc action failed actor={:?} action={:?} reason={}",
            actor_id, action, reason
        ),
        SimulationEvent::ActorMoved {
            actor_id,
            from,
            to,
            step_index,
            total_steps,
        } => format!(
            "actor moved {:?} ({}, {}, {}) -> ({}, {}, {}) step={}/{}",
            actor_id, from.x, from.y, from.z, to.x, to.y, to.z, step_index, total_steps
        ),
        SimulationEvent::ActorVisionUpdated {
            actor_id,
            active_map_id,
            visible_cells,
            explored_cells,
        } => format!(
            "vision updated actor={:?} map={} visible={} explored={}",
            actor_id,
            active_map_id
                .as_ref()
                .map(|map_id| map_id.as_str())
                .unwrap_or("none"),
            visible_cells.len(),
            explored_cells.len()
        ),
        SimulationEvent::PathComputed {
            actor_id,
            path_length,
        } => format!("path computed actor={:?} len={}", actor_id, path_length),
        SimulationEvent::InteractionOptionsResolved {
            actor_id,
            target_id,
            option_count,
        } => format!(
            "interaction options actor={:?} target={:?} count={}",
            actor_id, target_id, option_count
        ),
        SimulationEvent::InteractionApproachPlanned {
            actor_id,
            target_id,
            option_id,
            goal,
            path_length,
        } => format!(
            "interaction approach actor={:?} target={:?} option={} goal=({}, {}, {}) len={}",
            actor_id, target_id, option_id, goal.x, goal.y, goal.z, path_length
        ),
        SimulationEvent::InteractionStarted {
            actor_id,
            target_id,
            option_id,
        } => format!(
            "interaction started actor={:?} target={:?} option={}",
            actor_id, target_id, option_id
        ),
        SimulationEvent::InteractionSucceeded {
            actor_id,
            target_id,
            option_id,
        } => format!(
            "interaction ok actor={:?} target={:?} option={}",
            actor_id, target_id, option_id
        ),
        SimulationEvent::ContainerOpened {
            actor_id,
            target_id,
            container_id,
        } => format!(
            "container opened actor={:?} target={:?} container={}",
            actor_id, target_id, container_id
        ),
        SimulationEvent::InteractionFailed {
            actor_id,
            target_id,
            option_id,
            reason,
        } => format!(
            "interaction failed actor={:?} target={:?} option={} reason={}",
            actor_id, target_id, option_id, reason
        ),
        SimulationEvent::DialogueStarted {
            actor_id,
            target_id,
            dialogue_id,
        } => format!(
            "dialogue started actor={:?} target={:?} id={}",
            actor_id, target_id, dialogue_id
        ),
        SimulationEvent::DialogueAdvanced {
            actor_id,
            dialogue_id,
            node_id,
        } => format!(
            "dialogue advanced actor={:?} id={} node={}",
            actor_id, dialogue_id, node_id
        ),
        SimulationEvent::SceneTransitionRequested {
            actor_id,
            option_id,
            target_id,
            world_mode,
            ..
        } => format!(
            "scene transition actor={:?} option={} target={} mode={:?}",
            actor_id, option_id, target_id, world_mode
        ),
        SimulationEvent::LocationEntered {
            actor_id,
            location_id,
            map_id,
            entry_point_id,
            world_mode,
        } => format!(
            "location entered actor={:?} location={} map={} entry={} mode={:?}",
            actor_id, location_id, map_id, entry_point_id, world_mode
        ),
        SimulationEvent::ReturnedToOverworld {
            actor_id,
            active_outdoor_location_id,
        } => format!(
            "returned to overworld actor={:?} location={}",
            actor_id,
            active_outdoor_location_id.as_deref().unwrap_or("unknown")
        ),
        SimulationEvent::LocationUnlocked { location_id } => {
            format!("location unlocked {}", location_id)
        }
        SimulationEvent::PickupGranted {
            actor_id,
            target_id,
            item_id,
            count,
        } => format!(
            "pickup granted actor={:?} target={:?} item={} count={}",
            actor_id, target_id, item_id, count
        ),
        SimulationEvent::ActorDamaged {
            actor_id,
            target_actor,
            damage,
            remaining_hp,
        } => format!(
            "actor damaged attacker={:?} target={:?} damage={:.1} hp={:.1}",
            actor_id, target_actor, damage, remaining_hp
        ),
        SimulationEvent::ActorDefeated {
            actor_id,
            target_actor,
        } => format!(
            "actor defeated attacker={:?} target={:?}",
            actor_id, target_actor
        ),
        SimulationEvent::LootDropped {
            actor_id,
            target_actor,
            object_id,
            item_id,
            count,
            grid,
        } => format!(
            "loot dropped attacker={:?} target={:?} object={} item={} count={} grid=({}, {}, {})",
            actor_id, target_actor, object_id, item_id, count, grid.x, grid.y, grid.z
        ),
        SimulationEvent::ExperienceGranted {
            actor_id,
            amount,
            total_xp,
        } => format!(
            "xp granted actor={:?} amount={} total={}",
            actor_id, amount, total_xp
        ),
        SimulationEvent::ActorLeveledUp {
            actor_id,
            new_level,
            available_stat_points,
            available_skill_points,
        } => format!(
            "level up actor={:?} level={} stat_points={} skill_points={}",
            actor_id, new_level, available_stat_points, available_skill_points
        ),
        SimulationEvent::QuestStarted { actor_id, quest_id } => {
            format!("quest started actor={:?} quest={}", actor_id, quest_id)
        }
        SimulationEvent::QuestObjectiveProgressed {
            actor_id,
            quest_id,
            node_id,
            current,
            target,
        } => format!(
            "quest progress actor={:?} quest={} node={} {}/{}",
            actor_id, quest_id, node_id, current, target
        ),
        SimulationEvent::QuestCompleted { actor_id, quest_id } => {
            format!("quest completed actor={:?} quest={}", actor_id, quest_id)
        }
        SimulationEvent::RelationChanged {
            actor_id,
            target_id,
            disposition,
        } => format!(
            "relation changed actor={:?} target={:?} side={:?}",
            actor_id, target_id, disposition
        ),
    }
}
