//! 面板元信息 helper：负责面板标题、英文标签和默认宽度定义。

use super::*;

pub(in crate::game_ui) fn panel_title(panel: UiMenuPanel) -> &'static str {
    match panel {
        UiMenuPanel::Inventory => "背包",
        UiMenuPanel::Character => "角色",
        UiMenuPanel::Map => "地图",
        UiMenuPanel::Journal => "任务",
        UiMenuPanel::Skills => "技能",
        UiMenuPanel::Crafting => "制造",
        UiMenuPanel::Settings => "设置",
    }
}

pub(in crate::game_ui) fn panel_tab_label(panel: UiMenuPanel) -> &'static str {
    match panel {
        UiMenuPanel::Inventory => "Inventory",
        UiMenuPanel::Character => "Character",
        UiMenuPanel::Map => "Map",
        UiMenuPanel::Journal => "Quest",
        UiMenuPanel::Skills => "Skills",
        UiMenuPanel::Crafting => "Crafting",
        UiMenuPanel::Settings => "Menu",
    }
}

pub(in crate::game_ui) fn panel_width(panel: UiMenuPanel) -> f32 {
    match panel {
        UiMenuPanel::Inventory => INVENTORY_PANEL_WIDTH,
        UiMenuPanel::Skills => SKILLS_PANEL_WIDTH,
        _ => UI_PANEL_WIDTH,
    }
}
