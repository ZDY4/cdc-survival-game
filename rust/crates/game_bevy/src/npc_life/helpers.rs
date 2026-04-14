//! NPC life 辅助函数模块。
//! 负责 blackboard、planning context 与 smart object 选择辅助，不负责系统调度或 viewer 适配。

use std::collections::BTreeMap;

use bevy_ecs::prelude::Entity;
use game_core::{
    AiBlackboard, NpcFact, NpcGoalKey, NpcGoalScore, NpcPlanRequest, NpcPlanningContext,
};
use game_data::{
    GridCoord, NpcRole, ScheduleBlock, ScheduleDay, SettlementDefinition,
    SmartObjectAccessProfileDefinition, SmartObjectDefinition, SmartObjectKind,
};

use crate::reservations::SmartObjectReservations;

use super::components::{
    NeedState, NpcLifeState, NpcRuntimeBridgeState, PersonalityState, ReservationState,
    ScheduleState,
};

pub(super) fn route_duty_anchor(
    settlement: &SettlementDefinition,
    home_anchor: &str,
    route_id: &str,
) -> Option<String> {
    settlement
        .routes
        .iter()
        .find(|route| route.id == route_id)
        .and_then(|route| {
            route
                .anchors
                .iter()
                .find(|anchor| anchor.as_str() != home_anchor)
                .cloned()
                .or_else(|| route.anchors.first().cloned())
        })
}

pub(super) fn default_duty_anchor_for_role(
    settlement: &SettlementDefinition,
    role: NpcRole,
) -> Option<String> {
    match role {
        NpcRole::Guard => first_anchor_for_kind(settlement, SmartObjectKind::GuardPost),
        NpcRole::Cook => first_anchor_for_kind(settlement, SmartObjectKind::CanteenSeat),
        NpcRole::Doctor => first_anchor_for_kind(settlement, SmartObjectKind::MedicalStation),
        NpcRole::Resident => None,
    }
}

pub(super) fn resolve_anchor_grid(
    settlement: &SettlementDefinition,
    anchor_id: &str,
) -> Option<GridCoord> {
    settlement
        .anchors
        .iter()
        .find(|anchor| anchor.id == anchor_id)
        .map(|anchor| anchor.grid)
}

pub(super) fn first_anchor_for_kind(
    settlement: &SettlementDefinition,
    kind: SmartObjectKind,
) -> Option<String> {
    settlement
        .smart_objects
        .iter()
        .find(|object| object.kind == kind)
        .map(|object| object.anchor_id.clone())
}

pub(super) fn first_object_for_kind_for_role(
    settlement: &SettlementDefinition,
    kind: SmartObjectKind,
    role: NpcRole,
    access_profile: &SmartObjectAccessProfileDefinition,
) -> Option<String> {
    let role_tag = role_tag(role);
    let preferred_tags = preferred_tags_for_kind(access_profile, kind);
    settlement
        .smart_objects
        .iter()
        .find(|object| {
            object.kind == kind
                && preferred_tags
                    .iter()
                    .any(|tag| object.tags.iter().any(|object_tag| object_tag == tag))
        })
        .or_else(|| {
            settlement
                .smart_objects
                .iter()
                .find(|object| object.kind == kind && object.tags.iter().any(|tag| tag == role_tag))
        })
        .or_else(|| {
            settlement
                .smart_objects
                .iter()
                .find(|object| object.kind == kind)
        })
        .map(|object| object.id.clone())
}

pub(super) fn select_object_for_kind_for_role<'a>(
    settlement: &'a SettlementDefinition,
    kind: SmartObjectKind,
    role: NpcRole,
    access_profile: &SmartObjectAccessProfileDefinition,
    reservations: &SmartObjectReservations,
    owner: Entity,
) -> Option<&'a SmartObjectDefinition> {
    let role_tag = role_tag(role);
    let preferred_tags = preferred_tags_for_kind(access_profile, kind);
    select_available_object(
        settlement.smart_objects.iter().filter(move |object| {
            object.kind == kind
                && preferred_tags
                    .iter()
                    .any(|tag| object.tags.iter().any(|object_tag| object_tag == tag))
        }),
        reservations,
        owner,
    )
    .or_else(|| {
        select_available_object(
            settlement.smart_objects.iter().filter(move |object| {
                object.kind == kind && object.tags.iter().any(|tag| tag == role_tag)
            }),
            reservations,
            owner,
        )
    })
    .or_else(|| {
        select_available_object(
            settlement
                .smart_objects
                .iter()
                .filter(move |object| object.kind == kind),
            reservations,
            owner,
        )
    })
}

pub(super) fn select_available_object<'a>(
    candidates: impl Iterator<Item = &'a SmartObjectDefinition>,
    reservations: &SmartObjectReservations,
    owner: Entity,
) -> Option<&'a SmartObjectDefinition> {
    let mut first_available = None;
    for object in candidates {
        if reservations.holds(&object.id, owner) {
            return Some(object);
        }
        if first_available.is_none() && reservations.can_acquire(&object.id, owner) {
            first_available = Some(object);
        }
    }
    first_available
}

pub(super) fn object_anchor_id(
    settlement: &SettlementDefinition,
    object_id: &str,
) -> Option<String> {
    settlement
        .smart_objects
        .iter()
        .find(|object| object.id == object_id)
        .map(|object| object.anchor_id.clone())
}

pub(super) fn role_tag(role: NpcRole) -> &'static str {
    match role {
        NpcRole::Resident => "resident",
        NpcRole::Guard => "guard",
        NpcRole::Cook => "cook",
        NpcRole::Doctor => "doctor",
    }
}

pub(super) fn active_schedule_block(
    schedule: &[ScheduleBlock],
    day: ScheduleDay,
    minute_of_day: u16,
) -> Option<&ScheduleBlock> {
    schedule.iter().find(|block| {
        block.includes_day(day)
            && minute_in_window(minute_of_day, block.start_minute, block.end_minute)
    })
}

pub(super) fn minute_in_window(minute: u16, start_minute: u16, end_minute: u16) -> bool {
    minute >= start_minute && minute < end_minute
}

pub(super) fn non_empty(value: String) -> Option<String> {
    if value.trim().is_empty() {
        None
    } else {
        Some(value)
    }
}

pub(super) fn quantize_need(value: f32) -> u8 {
    value.round().clamp(0.0, 100.0) as u8
}

pub(super) fn build_ai_blackboard(
    life: &NpcLifeState,
    need: &NeedState,
    personality: &PersonalityState,
    schedule: &ScheduleState,
    reservations: &ReservationState,
    world_alert_active: bool,
    runtime_bridge: &NpcRuntimeBridgeState,
    active_guards: u32,
    min_guard_on_duty: u32,
    guard_post_available: bool,
    meal_object_available: bool,
    leisure_object_available: bool,
    medical_station_available: bool,
) -> AiBlackboard {
    let mut blackboard = AiBlackboard::default();
    blackboard.set_number("need.hunger", need.hunger);
    blackboard.set_number("need.energy", need.energy);
    blackboard.set_number("need.morale", need.morale);
    blackboard.set_number("personality.safety_bias", personality.safety_bias);
    blackboard.set_number("personality.social_bias", personality.social_bias);
    blackboard.set_number("personality.duty_bias", personality.duty_bias);
    blackboard.set_number("personality.comfort_bias", personality.comfort_bias);
    blackboard.set_number("personality.alertness_bias", personality.alertness_bias);
    blackboard.set_number("settlement.active_guards", active_guards as f32);
    blackboard.set_number("settlement.min_guard_on_duty", min_guard_on_duty as f32);
    blackboard.set_bool("schedule.on_shift", schedule.on_shift);
    blackboard.set_bool("schedule.shift_starting_soon", schedule.shift_starting_soon);
    blackboard.set_bool("schedule.meal_window_open", schedule.meal_window_open);
    blackboard.set_bool("schedule.quiet_hours", schedule.quiet_hours);
    blackboard.set_bool("world.alert_active", world_alert_active);
    blackboard.set_bool("combat.alert_active", runtime_bridge.combat_alert_active);
    blackboard.set_bool(
        "combat.replan_required",
        runtime_bridge.combat_replan_required,
    );
    blackboard.set_bool(
        "combat.threat_active",
        runtime_bridge.combat_threat_actor_id.is_some(),
    );
    blackboard.set_optional_text(
        "combat.threat_actor_id",
        runtime_bridge
            .combat_threat_actor_id
            .map(|actor_id| actor_id.0.to_string()),
    );
    blackboard.set_optional_text(
        "combat.last_target_actor_id",
        runtime_bridge
            .last_combat_target_actor_id
            .map(|actor_id| actor_id.0.to_string()),
    );
    blackboard.set_optional_text(
        "combat.last_outcome",
        runtime_bridge.last_combat_outcome.clone(),
    );
    blackboard.set_number(
        "combat.last_damage_taken",
        runtime_bridge.last_damage_taken.unwrap_or(0.0),
    );
    blackboard.set_number(
        "combat.last_damage_dealt",
        runtime_bridge.last_damage_dealt.unwrap_or(0.0),
    );
    blackboard.set_bool(
        "reservation.bed.active",
        life.bed_id
            .as_ref()
            .map(|id| reservations.active.contains(id))
            .unwrap_or(false),
    );
    blackboard.set_bool(
        "reservation.meal_object.active",
        life.meal_object_id
            .as_ref()
            .map(|id| reservations.active.contains(id))
            .unwrap_or(false),
    );
    blackboard.set_bool(
        "settlement.guard_coverage_insufficient",
        life.role == NpcRole::Guard && schedule.on_shift && active_guards < min_guard_on_duty,
    );
    blackboard.set_bool("availability.guard_post", guard_post_available);
    blackboard.set_bool("availability.meal_object", meal_object_available);
    blackboard.set_bool("availability.leisure_object", leisure_object_available);
    blackboard.set_bool("availability.medical_station", medical_station_available);
    blackboard.set_bool("availability.patrol_route", life.duty_route_id.is_some());
    blackboard.set_optional_text("anchor.current", life.current_anchor.clone());
    blackboard.set_text("anchor.home", life.home_anchor.clone());
    blackboard.set_optional_text("anchor.duty", life.duty_anchor.clone());
    blackboard.set_optional_text("anchor.canteen", life.canteen_anchor.clone());
    blackboard.set_optional_text("anchor.leisure", life.leisure_anchor.clone());
    blackboard.set_optional_text("anchor.alarm", life.alarm_anchor.clone());
    blackboard
}

fn preferred_tags_for_kind<'a>(
    access_profile: &'a SmartObjectAccessProfileDefinition,
    kind: SmartObjectKind,
) -> &'a [String] {
    access_profile
        .rules
        .iter()
        .find(|rule| rule.kind == kind)
        .map(|rule| rule.preferred_tags.as_slice())
        .unwrap_or(&[])
}

pub(super) fn build_decision_summary(
    selected_goal: &NpcGoalKey,
    goal_scores: &[NpcGoalScore],
    facts: &[NpcFact],
    planned: bool,
) -> String {
    let top_scores: Vec<String> = goal_scores
        .iter()
        .take(3)
        .map(|score| format!("{:?}:{:.3}", score.goal, score.score))
        .collect();
    let top_facts: Vec<String> = facts
        .iter()
        .take(4)
        .map(|fact| format!("{:?}", fact))
        .collect();
    let plan_state = if planned { "planned" } else { "fallback" };
    format!(
        "goal={selected_goal:?} state={plan_state} top_scores=[{}] facts=[{}]",
        top_scores.join(","),
        top_facts.join(",")
    )
}

pub(super) fn build_planning_context(
    settlement: &SettlementDefinition,
    request: &NpcPlanRequest,
    current_anchor: Option<String>,
) -> NpcPlanningContext {
    let mut context =
        NpcPlanningContext::from_plan_request(request).with_current_anchor(current_anchor.clone());
    let Some(current_anchor) = current_anchor else {
        return context;
    };

    let anchor_lookup: BTreeMap<&str, GridCoord> = settlement
        .anchors
        .iter()
        .map(|anchor| (anchor.id.as_str(), anchor.grid))
        .collect();

    for anchor in [
        request.home_anchor.as_deref(),
        request.duty_anchor.as_deref(),
        request.canteen_anchor.as_deref(),
        request.leisure_anchor.as_deref(),
        request.alarm_anchor.as_deref(),
    ]
    .into_iter()
    .flatten()
    {
        if let Some(minutes) =
            travel_minutes_between_anchors(&anchor_lookup, &current_anchor, anchor)
        {
            context.register_reachable_anchor(anchor.to_string(), minutes);
        }
    }

    context
}

pub(super) fn travel_minutes_between_anchors(
    anchors: &BTreeMap<&str, GridCoord>,
    from_anchor: &str,
    to_anchor: &str,
) -> Option<u32> {
    let from = anchors.get(from_anchor)?;
    let to = anchors.get(to_anchor)?;
    let distance =
        (from.x - to.x).abs() as u32 + (from.y - to.y).abs() as u32 + (from.z - to.z).abs() as u32;
    Some(distance.saturating_mul(5))
}
