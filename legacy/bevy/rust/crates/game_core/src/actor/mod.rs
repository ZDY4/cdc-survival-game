//! Actor 运行时内核模块。
//! 负责 actor 记录与注册表能力，不负责运行时 AI 控制器定义。

mod record;
mod registry;

pub use record::ActorRecord;
pub(crate) use record::ActorRegistrySnapshot;
pub use registry::ActorRegistry;
