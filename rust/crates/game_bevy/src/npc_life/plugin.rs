//! NPC life 插件装配模块。
//! 负责注册 life 域调度与资源初始化，不负责具体规划或桥接实现。

use bevy_app::prelude::*;
use bevy_ecs::prelude::SystemSet;

use super::systems;

#[derive(SystemSet, Debug, Hash, PartialEq, Eq, Clone)]
pub enum NpcLifeUpdateSet {
    RuntimeState,
}

pub struct NpcLifePlugin;

impl Plugin for NpcLifePlugin {
    fn build(&self, app: &mut App) {
        systems::configure(app);
    }
}

pub struct SettlementSimulationPlugin;

impl Plugin for SettlementSimulationPlugin {
    fn build(&self, app: &mut App) {
        systems::initialize_resources(app);
    }
}
