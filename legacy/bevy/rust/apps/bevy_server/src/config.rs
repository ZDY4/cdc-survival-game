use bevy_ecs::prelude::*;
use game_core::SimulationRuntime;

#[derive(Resource, Debug, Clone)]
pub struct ServerConfig {
    pub tick_rate_hz: u16,
}

impl Default for ServerConfig {
    fn default() -> Self {
        Self { tick_rate_hz: 60 }
    }
}

#[derive(Resource, Debug)]
pub struct ServerSimulationRuntime(pub SimulationRuntime);

#[derive(Resource, Debug, Clone, PartialEq, Eq)]
pub enum ServerStartupState {
    Ready,
    Failed { error: String },
}

impl Default for ServerStartupState {
    fn default() -> Self {
        Self::Ready
    }
}

#[derive(Resource, Debug, Clone)]
pub struct ServerVisionConfig {
    pub default_radius: i32,
}

impl Default for ServerVisionConfig {
    fn default() -> Self {
        Self { default_radius: 10 }
    }
}

#[derive(Resource, Debug, Clone, Default)]
pub struct NpcDebugReportState {
    pub ticks: u32,
    pub printed_frames: u32,
}

#[derive(Resource, Debug, Clone, PartialEq, Eq, Default)]
pub struct EconomySmokeReport {
    pub learned_skill_id: Option<String>,
    pub crafted_recipe_id: Option<String>,
    pub crafted_output_item_id: Option<u32>,
    pub bought_item_id: Option<u32>,
    pub sold_item_id: Option<u32>,
}
