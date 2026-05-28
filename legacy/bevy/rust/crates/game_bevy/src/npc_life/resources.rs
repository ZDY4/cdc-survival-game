//! NPC life 域资源定义。
//! 负责承载时钟、聚落上下文与调试快照资源，不负责规划或战斗逻辑本身。

use bevy_ecs::prelude::Resource;
use game_data::ScheduleDay;

use super::debug_types::SettlementDebugEntry;

#[derive(Resource, Debug, Clone, PartialEq, Eq)]
pub struct SimClock {
    pub day: ScheduleDay,
    pub minute_of_day: u16,
    pub offline_step_minutes: u16,
    pub total_days: u32,
}

impl Default for SimClock {
    fn default() -> Self {
        Self {
            day: ScheduleDay::Monday,
            minute_of_day: 7 * 60,
            offline_step_minutes: 5,
            total_days: 1,
        }
    }
}

#[derive(Resource, Debug, Clone, PartialEq, Eq, Default)]
pub struct WorldAlertState {
    pub active: bool,
}

#[derive(Resource, Debug, Clone, PartialEq, Eq, Default)]
pub struct SettlementContext {
    pub player_present: bool,
}

#[derive(Resource, Debug, Clone, PartialEq, Default)]
pub struct SettlementDebugSnapshot {
    pub entries: Vec<SettlementDebugEntry>,
}
