//! 运行时 AI 控制器集合模块。
//! 负责聚合具体控制器实现，不负责公共 trait 或执行结果定义。

mod follow_goal;
mod noop;
mod one_shot_interact;

pub use follow_goal::FollowRuntimeGoalController;
pub use noop::NoopAiController;
pub use one_shot_interact::OneShotInteractController;
