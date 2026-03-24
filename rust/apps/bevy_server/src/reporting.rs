use bevy_app::AppExit;
use bevy_ecs::prelude::*;

use crate::config::NpcDebugReportState;
use game_bevy::{
    AiCombatProfile, BehaviorProfile, CampId, CharacterArchetypeComponent, CharacterDefinitionId,
    CharacterSpawnRejected, DisplayName, Disposition, GridPosition, Level, LootTable,
    SettlementDebugSnapshot, SimClock, XpReward,
};

pub fn report_npc_life_debug_snapshot(
    mut debug_state: ResMut<NpcDebugReportState>,
    clock: Res<SimClock>,
    snapshot: Res<SettlementDebugSnapshot>,
) {
    debug_state.ticks += 1;
    if snapshot.entries.is_empty() {
        return;
    }
    if debug_state.printed_frames > 0 && debug_state.ticks % 10 != 0 {
        return;
    }
    debug_state.printed_frames += 1;

    println!(
        "npc_debug_snapshot day={:?} minute={} entries={}",
        clock.day,
        clock.minute_of_day,
        snapshot.entries.len(),
    );
    for entry in snapshot.entries.iter().take(6) {
        let top_scores = entry
            .goal_scores
            .iter()
            .take(3)
            .map(|score| format!("{:?}:{}", score.goal, score.score))
            .collect::<Vec<_>>()
            .join(",");
        let top_facts = entry
            .facts
            .iter()
            .take(5)
            .map(|fact| format!("{fact:?}"))
            .collect::<Vec<_>>()
            .join(",");
        let pending = entry
            .pending_plan
            .iter()
            .map(|step| format!("{:?}@{:?}", step.action, step.target_anchor))
            .collect::<Vec<_>>()
            .join(" -> ");
        println!(
            "npc entity={:?} role={:?} goal={:?} action={:?}/{:?} anchor={:?} needs(h/e/m)={}/{}/{} on_shift={} replan={} top_scores=[{}] facts=[{}] pending=[{}] summary={}",
            entry.entity,
            entry.role,
            entry.goal,
            entry.action,
            entry.action_phase,
            entry.current_anchor,
            entry.need_hunger,
            entry.need_energy,
            entry.need_morale,
            entry.on_shift,
            entry.replan_required,
            top_scores,
            top_facts,
            pending,
            entry.decision_summary,
        );
    }
}

pub fn report_spawned_characters_and_exit(
    spawned_characters: Query<(
        Entity,
        &CharacterDefinitionId,
        &CharacterArchetypeComponent,
        &Disposition,
        &CampId,
        &DisplayName,
        &Level,
        &BehaviorProfile,
        &AiCombatProfile,
        &XpReward,
        &LootTable,
        &GridPosition,
    )>,
    mut rejections: MessageReader<CharacterSpawnRejected>,
    debug_state: Res<NpcDebugReportState>,
    snapshot: Res<SettlementDebugSnapshot>,
    mut already_reported: Local<bool>,
    mut app_exit: MessageWriter<AppExit>,
) {
    if !*already_reported {
        let mut spawned_count = 0usize;
        for (
            entity,
            definition_id,
            archetype,
            disposition,
            camp_id,
            display_name,
            level,
            behavior,
            ai,
            xp_reward,
            loot,
            grid_position,
        ) in &spawned_characters
        {
            spawned_count += 1;
            println!(
                "spawned entity={entity:?} id={} archetype={:?} disposition={:?} camp={} name={} level={} grid=({}, {}, {}) behavior={} xp={} loot={} ai_attack_range={}",
                definition_id.0,
                archetype.0,
                disposition.0,
                camp_id.0,
                display_name.0,
                level.0,
                grid_position.0.x,
                grid_position.0.y,
                grid_position.0.z,
                behavior.0,
                xp_reward.0,
                loot.0.len(),
                ai.0.attack_range,
            );
        }

        for rejection in rejections.read() {
            println!(
                "character spawn rejected: definition_id={} reason={}",
                rejection.definition_id, rejection.reason
            );
        }

        if spawned_count > 0 {
            *already_reported = true;
        }
        return;
    }

    for rejection in rejections.read() {
        println!(
            "character spawn rejected: definition_id={} reason={}",
            rejection.definition_id, rejection.reason
        );
    }

    let enough_debug_cycles = debug_state.printed_frames >= 2;
    let has_npc_debug_entries = !snapshot.entries.is_empty();
    let timeout_reached = debug_state.ticks >= 600;
    if (enough_debug_cycles && has_npc_debug_entries) || timeout_reached {
        if timeout_reached && !has_npc_debug_entries {
            println!("npc_debug_snapshot timeout reached without npc entries; shutting down");
        }
        app_exit.write(AppExit::Success);
    }
}
