use crate::state::ViewerHudPage;

pub(crate) fn footer_hint(page: ViewerHudPage) -> &'static str {
    match page {
        ViewerHudPage::Overview => "F1-7切页 · Ctrl+P控制/观察切换 · H隐藏HUD · /帮助 · ~控制台 · show fps 开关右上角 FPS",
        ViewerHudPage::SelectedActor => {
            "F1-7切页 · Ctrl+P控制/观察切换 · H隐藏HUD · /帮助 · ~控制台 · A切换自动tick · V切换调试叠层"
        }
        ViewerHudPage::World => "F1-7切页 · Ctrl+P控制/观察切换 · H隐藏HUD · /帮助 · ~控制台 · V切换调试叠层",
        ViewerHudPage::Interaction => {
            "F1-7切页 · Ctrl+P控制/观察切换 · H隐藏HUD · /帮助 · ~控制台 · /切换详细帮助"
        }
        ViewerHudPage::Events => {
            "F1-7切页 · Ctrl+P控制/观察切换 · H隐藏HUD · /帮助 · ~控制台 · [ / ] 切换事件过滤"
        }
        ViewerHudPage::Ai => "F1-7切页 · Ctrl+P控制/观察切换 · H隐藏HUD · /帮助 · ~控制台",
        ViewerHudPage::Performance => {
            "F1-7切页 · Ctrl+P控制/观察切换 · H隐藏HUD · /帮助 · ~控制台 · show fps 开关右上角 FPS · 仅当前页统计函数耗时"
        }
    }
}
