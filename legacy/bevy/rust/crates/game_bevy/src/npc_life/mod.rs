//! NPC 日常生活域模块。
//! 负责汇总 life 域类型、调试结构与系统插件，不负责在线 runtime 适配实现。

mod components;
mod debug_types;
mod helpers;
mod plugin;
mod resources;
mod systems;

#[cfg(test)]
mod tests;

pub use components::{
    AiBehaviorProfileComponent, BackgroundLifeState, LifeProfileComponent, NeedState,
    NpcActiveOfflineAction, NpcLifeState, NpcPlannedActionQueue, NpcPlannedGoal, NpcRuntimeAiMode,
    NpcRuntimeBridgeState, PersonalityState, ReservationState, ResolvedLifeProfileComponent,
    RuntimeActorLink, ScheduleState, SmartObjectAccessProfileComponent,
};
pub use debug_types::{NpcDecisionTrace, PlannedActionDebug, SettlementDebugEntry};
pub use plugin::{NpcLifePlugin, NpcLifeUpdateSet, SettlementSimulationPlugin};
pub use resources::{SettlementContext, SettlementDebugSnapshot, SimClock, WorldAlertState};
