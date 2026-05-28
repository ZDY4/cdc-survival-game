//! NPC life 实体初始化系统。
//! 负责把角色 life profile 解析为运行时组件，不负责后续规划推进或 viewer 在线同步。

use bevy_app::App;
use bevy_ecs::prelude::*;
use game_data::{
    resolve_ai_behavior_profile, resolve_character_life_profile, NpcRole, SettlementId,
    SmartObjectKind,
};

use crate::{AiDefinitions, SettlementDefinitions, SmartObjectReservations};

use super::super::components::{
    AiBehaviorProfileComponent, BackgroundLifeState, LifeProfileComponent, NeedState,
    NpcActiveOfflineAction, NpcLifeState, NpcPlannedActionQueue, NpcPlannedGoal,
    NpcRuntimeBridgeState, PersonalityState, ReservationState, ResolvedLifeProfileComponent,
    ScheduleState, SmartObjectAccessProfileComponent,
};
use super::super::debug_types::NpcDecisionTrace;
use super::super::helpers::{
    default_duty_anchor_for_role, first_anchor_for_kind, first_object_for_kind_for_role, non_empty,
    route_duty_anchor,
};
use super::super::resources::{
    SettlementContext, SettlementDebugSnapshot, SimClock, WorldAlertState,
};

pub(super) fn initialize_resources(app: &mut App) {
    app.init_resource::<SimClock>()
        .init_resource::<WorldAlertState>()
        .init_resource::<SettlementContext>()
        .init_resource::<SmartObjectReservations>()
        .init_resource::<SettlementDebugSnapshot>();
}

pub(super) fn initialize_npc_life_entities(
    mut commands: Commands,
    settlements: Option<Res<SettlementDefinitions>>,
    ai_definitions: Option<Res<AiDefinitions>>,
    query: Query<(Entity, &LifeProfileComponent), Without<NpcLifeState>>,
) {
    let Some(settlements) = settlements else {
        return;
    };
    let Some(ai_definitions) = ai_definitions else {
        return;
    };

    for (entity, profile_component) in &query {
        let profile = &profile_component.0;
        let Ok(resolved_life) = resolve_character_life_profile(profile, &ai_definitions.0) else {
            continue;
        };
        let settlement = match settlements
            .0
            .get(&SettlementId(profile.settlement_id.clone()))
        {
            Some(settlement) => settlement,
            None => continue,
        };
        let duty_anchor = route_duty_anchor(
            settlement,
            &resolved_life.home_anchor,
            &resolved_life.duty_route_id,
        )
        .or_else(|| default_duty_anchor_for_role(settlement, profile.role));
        let canteen_anchor = first_anchor_for_kind(settlement, SmartObjectKind::CanteenSeat);
        let leisure_anchor = first_anchor_for_kind(settlement, SmartObjectKind::RecreationSpot);
        let alarm_anchor = first_anchor_for_kind(settlement, SmartObjectKind::AlarmPoint);
        let guard_post_id = if profile.role == NpcRole::Guard {
            first_object_for_kind_for_role(
                settlement,
                SmartObjectKind::GuardPost,
                profile.role,
                &resolved_life.smart_object_access_profile,
            )
        } else {
            None
        };
        let Ok(ai_behavior_profile) = resolve_ai_behavior_profile(
            &ai_definitions.0,
            &profile.ai_behavior_profile_id.clone().into(),
        ) else {
            continue;
        };

        commands.entity(entity).insert((
            AiBehaviorProfileComponent(ai_behavior_profile),
            ResolvedLifeProfileComponent(resolved_life.clone()),
            PersonalityState::from(&resolved_life.personality_profile),
            SmartObjectAccessProfileComponent(resolved_life.smart_object_access_profile.clone()),
            NpcLifeState {
                settlement_id: profile.settlement_id.clone(),
                role: profile.role,
                home_anchor: resolved_life.home_anchor.clone(),
                duty_anchor,
                duty_route_id: non_empty(resolved_life.duty_route_id.clone()),
                canteen_anchor,
                leisure_anchor,
                alarm_anchor,
                guard_post_id,
                bed_id: first_object_for_kind_for_role(
                    settlement,
                    SmartObjectKind::Bed,
                    profile.role,
                    &resolved_life.smart_object_access_profile,
                ),
                meal_object_id: first_object_for_kind_for_role(
                    settlement,
                    SmartObjectKind::CanteenSeat,
                    profile.role,
                    &resolved_life.smart_object_access_profile,
                ),
                leisure_object_id: first_object_for_kind_for_role(
                    settlement,
                    SmartObjectKind::RecreationSpot,
                    profile.role,
                    &resolved_life.smart_object_access_profile,
                ),
                current_anchor: Some(resolved_life.home_anchor.clone()),
                replan_required: true,
                online: false,
            },
            NeedState::from_profile(&resolved_life.need_profile),
            ScheduleState::default(),
            NpcPlannedGoal::default(),
            NpcPlannedActionQueue::default(),
            NpcActiveOfflineAction::default(),
            ReservationState::default(),
            NpcRuntimeBridgeState::default(),
            BackgroundLifeState::default(),
            NpcDecisionTrace::default(),
        ));
    }
}

pub(super) fn sync_reservation_catalog_system(
    settlements: Option<Res<SettlementDefinitions>>,
    mut reservations: ResMut<SmartObjectReservations>,
) {
    let Some(settlements) = settlements else {
        return;
    };
    reservations.sync_settlement_catalog(&settlements.0);
}
