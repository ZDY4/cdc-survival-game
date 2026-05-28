//! 运行时 AI 控制器模块。
//! 负责运行时一步动作执行接口和控制器导出，不负责 actor 注册表或高层目标规划。

pub mod controllers;

use game_data::ActorId;

use crate::simulation::Simulation;

pub use controllers::{FollowRuntimeGoalController, NoopAiController, OneShotInteractController};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct RuntimeAiStepResult {
    pub performed: bool,
}

impl RuntimeAiStepResult {
    pub const fn performed() -> Self {
        Self { performed: true }
    }

    pub const fn idle() -> Self {
        Self { performed: false }
    }
}

pub trait RuntimeAiController: Send + Sync + std::fmt::Debug {
    fn execute_turn_step(
        &mut self,
        actor_id: ActorId,
        simulation: &mut Simulation,
    ) -> RuntimeAiStepResult;
}
