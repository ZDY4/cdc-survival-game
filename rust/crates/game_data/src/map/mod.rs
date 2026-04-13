//! 地图共享模型的门面模块，统一组织 schema、加载、校验与对象辅助逻辑。

mod interaction;
mod library;
mod object;
mod types;
mod validation;

pub use library::*;
pub use object::*;
pub use types::*;
pub use validation::*;

#[cfg(test)]
mod tests;
