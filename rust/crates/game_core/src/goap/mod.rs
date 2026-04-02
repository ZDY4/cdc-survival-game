pub mod actions;
pub mod behavior;
pub mod context;
pub mod facts;
pub mod goals;
pub mod offline_sim;
pub mod plan_runtime;
pub mod planner;

use std::borrow::Cow;
use std::collections::BTreeSet;
use std::fmt;

use game_data::{
    AiBehaviorProfile, AiNeedEffectDefinition, AiWorldStateEffectDefinition, BuiltinAiExecutorKind,
    GridCoord, MapId, NpcRole,
};

pub use behavior::AiBlackboard;
pub use context::NpcPlanningContext;
pub use facts::rebuild_facts;
pub use offline_sim::{advance_offline_sim, NpcOfflineSimState, OfflineSimAdvanceResult};
pub use plan_runtime::{
    tick_offline_action, ActionExecutionPhase, ActionTickResult, OfflineActionState,
};
pub use planner::{
    build_plan, build_plan_for_context, build_plan_for_goal, build_plan_for_goal_with_context,
};

macro_rules! npc_string_id {
    ($name:ident) => {
        #[derive(
            Clone,
            PartialEq,
            Eq,
            PartialOrd,
            Ord,
            Hash,
            serde::Serialize,
            serde::Deserialize,
            Default,
        )]
        #[serde(transparent)]
        pub struct $name(pub Cow<'static, str>);

        impl $name {
            pub fn as_str(&self) -> &str {
                self.0.as_ref()
            }
        }

        impl fmt::Debug for $name {
            fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
                f.write_str(self.as_str())
            }
        }

        impl fmt::Display for $name {
            fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
                f.write_str(self.as_str())
            }
        }

        impl From<&str> for $name {
            fn from(value: &str) -> Self {
                Self(Cow::Owned(value.to_string()))
            }
        }

        impl From<String> for $name {
            fn from(value: String) -> Self {
                Self(Cow::Owned(value))
            }
        }
    };
}

npc_string_id!(NpcFact);
npc_string_id!(NpcGoalKey);
npc_string_id!(NpcActionKey);

#[allow(non_upper_case_globals)]
impl NpcFact {
    pub const Hungry: Self = Self(Cow::Borrowed("hungry"));
    pub const VeryHungry: Self = Self(Cow::Borrowed("very_hungry"));
    pub const Sleepy: Self = Self(Cow::Borrowed("sleepy"));
    pub const Exhausted: Self = Self(Cow::Borrowed("exhausted"));
    pub const NeedMorale: Self = Self(Cow::Borrowed("need_morale"));
    pub const OnShift: Self = Self(Cow::Borrowed("on_shift"));
    pub const ShiftStartingSoon: Self = Self(Cow::Borrowed("shift_starting_soon"));
    pub const ThreatDetected: Self = Self(Cow::Borrowed("threat_detected"));
    pub const MealWindowOpen: Self = Self(Cow::Borrowed("meal_window_open"));
    pub const AtHome: Self = Self(Cow::Borrowed("at_home"));
    pub const AtDutyArea: Self = Self(Cow::Borrowed("at_duty_area"));
    pub const HasReservedBed: Self = Self(Cow::Borrowed("has_reserved_bed"));
    pub const HasReservedMealSeat: Self = Self(Cow::Borrowed("has_reserved_meal_seat"));
    pub const GuardCoverageInsufficient: Self = Self(Cow::Borrowed("guard_coverage_insufficient"));
}

#[allow(non_upper_case_globals)]
impl NpcGoalKey {
    pub const RespondThreat: Self = Self(Cow::Borrowed("respond_threat"));
    pub const PreserveLife: Self = Self(Cow::Borrowed("preserve_life"));
    pub const SatisfyShift: Self = Self(Cow::Borrowed("satisfy_shift"));
    pub const EatMeal: Self = Self(Cow::Borrowed("eat_meal"));
    pub const Sleep: Self = Self(Cow::Borrowed("sleep"));
    pub const RecoverMorale: Self = Self(Cow::Borrowed("recover_morale"));
    pub const ReturnHome: Self = Self(Cow::Borrowed("return_home"));
    pub const IdleSafely: Self = Self(Cow::Borrowed("idle_safely"));
}

#[allow(non_upper_case_globals)]
impl NpcActionKey {
    pub const TravelToDutyArea: Self = Self(Cow::Borrowed("travel_to_duty_area"));
    pub const ReserveGuardPost: Self = Self(Cow::Borrowed("reserve_guard_post"));
    pub const StandGuard: Self = Self(Cow::Borrowed("stand_guard"));
    pub const PatrolRoute: Self = Self(Cow::Borrowed("patrol_route"));
    pub const TravelToCanteen: Self = Self(Cow::Borrowed("travel_to_canteen"));
    pub const EatMeal: Self = Self(Cow::Borrowed("eat_meal"));
    pub const RestockMealService: Self = Self(Cow::Borrowed("restock_meal_service"));
    pub const TreatPatients: Self = Self(Cow::Borrowed("treat_patients"));
    pub const TravelToLeisure: Self = Self(Cow::Borrowed("travel_to_leisure"));
    pub const Relax: Self = Self(Cow::Borrowed("relax"));
    pub const TravelHome: Self = Self(Cow::Borrowed("travel_home"));
    pub const ReserveBed: Self = Self(Cow::Borrowed("reserve_bed"));
    pub const Sleep: Self = Self(Cow::Borrowed("sleep"));
    pub const RaiseAlarm: Self = Self(Cow::Borrowed("raise_alarm"));
    pub const RespondAlarm: Self = Self(Cow::Borrowed("respond_alarm"));
    pub const IdleSafely: Self = Self(Cow::Borrowed("idle_safely"));
}

#[derive(Debug, Clone, PartialEq, Default)]
pub struct NpcGoalScore {
    pub goal: NpcGoalKey,
    pub score: i32,
    pub matched_rule_ids: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Default)]
pub struct NpcPlanRequest {
    pub role: NpcRole,
    pub behavior: AiBehaviorProfile,
    pub blackboard: AiBlackboard,
    pub facts: Vec<NpcFact>,
    pub home_anchor: Option<String>,
    pub duty_anchor: Option<String>,
    pub canteen_anchor: Option<String>,
    pub leisure_anchor: Option<String>,
    pub alarm_anchor: Option<String>,
    pub guard_post_id: Option<String>,
    pub bed_id: Option<String>,
    pub meal_object_id: Option<String>,
    pub leisure_object_id: Option<String>,
    pub medical_station_id: Option<String>,
    pub patrol_route_id: Option<String>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct NpcPlanStep {
    pub action: NpcActionKey,
    pub target_anchor: Option<String>,
    pub reservation_target: Option<String>,
    pub travel_minutes: u32,
    pub perform_minutes: u32,
    pub expected_facts: Vec<NpcFact>,
    pub executor_kind: BuiltinAiExecutorKind,
    pub need_effects: AiNeedEffectDefinition,
    pub world_state_effects: AiWorldStateEffectDefinition,
}

impl Eq for NpcPlanStep {}

#[derive(Debug, Clone, PartialEq)]
pub struct NpcPlanResult {
    pub selected_goal: NpcGoalKey,
    pub steps: Vec<NpcPlanStep>,
    pub total_cost: usize,
    pub facts: Vec<NpcFact>,
    pub debug_plan: String,
    pub planned: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum NpcExecutionMode {
    Online,
    #[default]
    Background,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NpcRuntimeActionState {
    pub step: NpcPlanStep,
    pub phase: ActionExecutionPhase,
    pub current_anchor: Option<String>,
    pub held_reservations: BTreeSet<String>,
    pub last_failure_reason: Option<String>,
    pub goal_grid: Option<GridCoord>,
}

impl NpcRuntimeActionState {
    pub fn from_offline_action(
        action: &OfflineActionState,
        held_reservations: BTreeSet<String>,
        last_failure_reason: Option<String>,
        goal_grid: Option<GridCoord>,
    ) -> Self {
        Self {
            step: action.step.clone(),
            phase: action.phase,
            current_anchor: action.current_anchor.clone(),
            held_reservations,
            last_failure_reason,
            goal_grid,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NpcBackgroundState {
    pub definition_id: Option<String>,
    pub display_name: String,
    pub map_id: Option<MapId>,
    pub grid_position: GridCoord,
    pub current_anchor: Option<String>,
    pub current_plan: Vec<NpcPlanStep>,
    pub plan_next_index: usize,
    pub current_action: Option<NpcRuntimeActionState>,
    pub held_reservations: BTreeSet<String>,
    pub hunger: u8,
    pub energy: u8,
    pub morale: u8,
    pub on_shift: bool,
    pub meal_window_open: bool,
    pub quiet_hours: bool,
    pub world_alert_active: bool,
}

pub fn apply_npc_action_effects(
    step: &NpcPlanStep,
    hunger: &mut f32,
    energy: &mut f32,
    morale: &mut f32,
) {
    *hunger = (*hunger + step.need_effects.hunger_delta).clamp(0.0, 100.0);
    *energy = (*energy + step.need_effects.energy_delta).clamp(0.0, 100.0);
    *morale = (*morale + step.need_effects.morale_delta).clamp(0.0, 100.0);
}
