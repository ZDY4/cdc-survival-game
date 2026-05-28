//! 任务日志面板渲染：展示当前任务、目标和进度。
use super::*;

pub(super) fn render_journal_panel(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    snapshot: &game_bevy::UiJournalSnapshot,
) {
    let body = panel_body(parent, UiMenuPanel::Journal);
    parent.commands().entity(body).with_children(|body| {
        if snapshot.quests.is_empty() {
            body.spawn(text_bundle(
                font,
                "当前没有进行中的任务",
                11.0,
                Color::WHITE,
            ));
        } else {
            for quest in &snapshot.quests {
                body.spawn(text_bundle(font, &quest.title, 11.0, Color::WHITE));
                if !quest.objective_text.trim().is_empty() {
                    body.spawn(text_bundle(
                        font,
                        &format!("目标: {}", quest.objective_text),
                        10.0,
                        Color::srgb(0.82, 0.86, 0.90),
                    ));
                }
                if quest.progress_target > 0 {
                    body.spawn(text_bundle(
                        font,
                        &format!("进度: {}/{}", quest.progress_current, quest.progress_target),
                        10.0,
                        Color::srgb(0.62, 0.82, 0.68),
                    ));
                }
            }
        }
    });
}
