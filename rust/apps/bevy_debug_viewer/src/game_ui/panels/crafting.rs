//! 制作面板渲染：展示可用配方并触发制作动作。
use super::*;

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
