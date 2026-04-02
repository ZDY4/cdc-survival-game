//! HUD 页脚拼装：负责底部补充状态文本与各类调试摘要的格式化输出。

use crate::state::ViewerHudPage;

pub(crate) fn footer_hint(page: ViewerHudPage) -> &'static str {
    match page {
        ViewerHudPage::Overview => "F1-7切页 · H隐藏HUD · /帮助 · ~控制台 · show fps 开关右上角 FPS · ob mode 切换控制/观察",
        ViewerHudPage::SelectedActor => {
            "F1-7切页 · H隐藏HUD · /帮助 · ~控制台 · A切换自动tick · V切换调试叠层 · ob mode 切换控制/观察"
        }
        ViewerHudPage::World => "F1-7切页 · H隐藏HUD · /帮助 · ~控制台 · V切换调试叠层 · ob mode 切换控制/观察",
        ViewerHudPage::Interaction => {
            "F1-7切页 · H隐藏HUD · /帮助 · ~控制台 · /切换详细帮助 · ob mode 切换控制/观察"
        }
        ViewerHudPage::Events => {
            "F1-7切页 · H隐藏HUD · /帮助 · ~控制台 · [ / ] 切换事件过滤 · ob mode 切换控制/观察"
        }
        ViewerHudPage::Ai => "F1-7切页 · H隐藏HUD · /帮助 · ~控制台 · ob mode 切换控制/观察",
        ViewerHudPage::Performance => {
            "F1-7切页 · H隐藏HUD · /帮助 · ~控制台 · show fps 开关右上角 FPS · ob mode 切换控制/观察 · 仅当前页统计函数耗时"
        }
    }
}
