//! 角色面板渲染：展示属性点与属性提升入口。
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
