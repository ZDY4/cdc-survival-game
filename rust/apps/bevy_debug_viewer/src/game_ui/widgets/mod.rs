//! UI widget 门面：按职责拆分通用按钮/文本、详情展示、面板元信息、快捷栏辅助等子模块。

use super::*;

mod base;
mod detail;
mod hotbar;
mod inventory_detail;
mod panel;
mod skill_detail;

pub(super) use base::*;
pub(super) use detail::*;
pub(super) use hotbar::*;
pub(super) use inventory_detail::*;
pub(super) use panel::*;
pub(super) use skill_detail::*;
