//! 负责角色属性、任务日志与制作面板的渲染逻辑。
use super::*;

pub(super) fn render_character_panel(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    snapshot: &game_bevy::UiCharacterSnapshot,
) {
    let body = panel_body(parent, UiMenuPanel::Character);
    parent.commands().entity(body).with_children(|body| {
        body.spawn(text_bundle(
            font,
            &format!("可用属性点 {}", snapshot.available_points),
            11.0,
            Color::WHITE,
        ));
        for attribute in ["strength", "agility", "constitution"] {
            let value = snapshot.attributes.get(attribute).copied().unwrap_or(0);
            body.spawn(text_bundle(
                font,
                &format!("{attribute}: {value}"),
                11.0,
                Color::WHITE,
            ));
            body.spawn(action_button(
                font,
                &format!("提升 {attribute}"),
                GameUiButtonAction::AllocateAttribute(attribute.to_string()),
            ));
        }
    });
}

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

pub(super) fn render_crafting_panel(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    snapshot: &game_bevy::UiCraftingSnapshot,
) {
    let body = panel_body(parent, UiMenuPanel::Crafting);
    parent.commands().entity(body).with_children(|body| {
        if snapshot.recipe_names.is_empty() {
            body.spawn(text_bundle(font, "当前没有可制造配方", 11.0, Color::WHITE));
        } else {
            for (recipe_id, recipe_name) in &snapshot.recipe_names {
                body.spawn(action_button(
                    font,
                    recipe_name,
                    GameUiButtonAction::CraftRecipe(recipe_id.clone()),
                ));
            }
        }
    });
}
