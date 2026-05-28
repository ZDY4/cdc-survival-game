//! Utility AI 模块。
//! 负责生活 AI 的 goal 打分与选择，不负责 GOAP 规划执行或战斗启发式决策。

pub mod context;
pub mod scoring;
pub mod selector;

pub use context::NpcUtilityContext;
pub use scoring::{score_goal, score_goal_for_context, score_goals, score_goals_for_context};
pub use selector::{select_goal, select_goal_for_context};
