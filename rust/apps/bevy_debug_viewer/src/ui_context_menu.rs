use bevy::prelude::*;
use bevy::text::{Justify, LineBreak, TextLayout};
use bevy::ui::{FocusPolicy, RelativeCursorPosition};

use crate::state::{viewer_ui_passthrough_bundle, UiMouseBlocker, ViewerUiFont};

#[derive(Component, Debug, Clone, Copy, PartialEq, Eq, Default)]
pub(crate) struct ContextMenuItemDisabled;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum ContextMenuVariant {
    UiContext,
    WorldInteraction,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub(crate) struct ContextMenuStyle {
    pub width: f32,
    pub padding: f32,
    pub row_gap: f32,
    pub border_width: f32,
    pub item_min_height: f32,
    pub item_gap: f32,
    pub item_padding_x: f32,
    pub item_padding_y: f32,
    pub title_font_size: f32,
    pub subtitle_font_size: f32,
    pub item_font_size: f32,
    pub text_justify: Justify,
    pub highlight_primary: bool,
    pub show_header: bool,
    pub disabled_alpha: f32,
}

impl ContextMenuStyle {
    pub(crate) fn for_variant(variant: ContextMenuVariant) -> Self {
        match variant {
            ContextMenuVariant::UiContext => Self {
                width: 220.0,
                padding: 10.0,
                row_gap: 6.0,
                border_width: 1.0,
                item_min_height: 26.0,
                item_gap: 4.0,
                item_padding_x: 10.0,
                item_padding_y: 7.0,
                title_font_size: 10.2,
                subtitle_font_size: 9.8,
                item_font_size: 11.0,
                text_justify: Justify::Left,
                highlight_primary: true,
                show_header: true,
                disabled_alpha: 0.56,
            },
            ContextMenuVariant::WorldInteraction => Self {
                width: 70.0,
                padding: 6.0,
                row_gap: 0.0,
                border_width: 1.0,
                item_min_height: 20.0,
                item_gap: 2.0,
                item_padding_x: 6.0,
                item_padding_y: 2.0,
                title_font_size: 10.2,
                subtitle_font_size: 9.8,
                item_font_size: 10.5,
                text_justify: Justify::Left,
                highlight_primary: false,
                show_header: false,
                disabled_alpha: 0.56,
            },
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct ContextMenuItemVisual {
    pub label: String,
    pub is_primary: bool,
    pub is_disabled: bool,
}

pub(crate) fn context_menu_panel_color() -> Color {
    Color::srgba(0.06, 0.06, 0.055, 0.98)
}

pub(crate) fn context_menu_border_color() -> Color {
    Color::srgba(0.26, 0.26, 0.24, 1.0)
}

pub(crate) fn context_menu_text_color() -> Color {
    Color::srgba(0.92, 0.91, 0.88, 0.98)
}

pub(crate) fn context_menu_muted_text_color() -> Color {
    Color::srgba(0.72, 0.71, 0.68, 1.0)
}

pub(crate) fn context_menu_button_color(
    style: ContextMenuStyle,
    is_primary: bool,
    is_disabled: bool,
    interaction: Interaction,
) -> Color {
    if is_disabled {
        let mut color = Color::srgba(0.10, 0.10, 0.095, style.disabled_alpha);
        if matches!(interaction, Interaction::Hovered | Interaction::Pressed) {
            color = Color::srgba(0.10, 0.10, 0.095, style.disabled_alpha);
        }
        return color;
    }

    if style.highlight_primary && is_primary {
        match interaction {
            Interaction::Pressed => Color::srgba(0.18, 0.16, 0.10, 1.0),
            Interaction::Hovered => Color::srgba(0.24, 0.21, 0.12, 1.0),
            Interaction::None => Color::srgba(0.20, 0.18, 0.11, 1.0),
        }
    } else {
        match interaction {
            Interaction::Pressed => Color::srgba(0.10, 0.10, 0.09, 1.0),
            Interaction::Hovered => Color::srgba(0.18, 0.18, 0.17, 1.0),
            Interaction::None => Color::srgba(0.14, 0.14, 0.13, 1.0),
        }
    }
}

pub(crate) fn context_menu_root_node(style: ContextMenuStyle, position: Vec2) -> Node {
    Node {
        position_type: PositionType::Absolute,
        left: px(position.x),
        top: px(position.y),
        width: px(style.width),
        padding: UiRect::all(px(style.padding)),
        flex_direction: FlexDirection::Column,
        row_gap: px(style.row_gap),
        border: UiRect::all(px(style.border_width)),
        ..default()
    }
}

pub(crate) fn context_menu_button_node(style: ContextMenuStyle) -> Node {
    Node {
        width: Val::Percent(100.0),
        min_height: px(style.item_min_height),
        padding: UiRect::axes(px(style.item_padding_x), px(style.item_padding_y)),
        margin: UiRect::bottom(px(style.item_gap)),
        align_items: AlignItems::Center,
        justify_content: JustifyContent::FlexStart,
        ..default()
    }
}

pub(crate) fn context_menu_button_label_node() -> Node {
    Node {
        width: Val::Percent(100.0),
        ..default()
    }
}

pub(crate) fn context_menu_label_color(style: ContextMenuStyle, disabled: bool) -> Color {
    if disabled {
        Color::srgba(0.68, 0.67, 0.64, style.disabled_alpha)
    } else {
        let _ = style;
        context_menu_text_color()
    }
}

pub(crate) fn context_menu_header_text_bundle(
    font: &ViewerUiFont,
    text: &str,
    font_size: f32,
    color: Color,
) -> impl Bundle {
    (
        Text::new(text.to_string()),
        TextFont::from_font_size(font_size).with_font(font.0.clone()),
        TextColor(color),
        viewer_ui_passthrough_bundle(),
    )
}

pub(crate) fn spawn_context_menu_shell(
    parent: &mut ChildSpawnerCommands,
    style: ContextMenuStyle,
    position: Vec2,
    root_marker: impl Bundle,
    content: impl FnOnce(&mut ChildSpawnerCommands),
) {
    parent
        .spawn((
            context_menu_root_node(style, position),
            BackgroundColor(context_menu_panel_color()),
            BorderColor::all(context_menu_border_color()),
            FocusPolicy::Block,
            RelativeCursorPosition::default(),
            viewer_ui_passthrough_bundle(),
            UiMouseBlocker,
            root_marker,
        ))
        .with_children(content);
}

pub(crate) fn spawn_context_menu_button(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    style: ContextMenuStyle,
    item: &ContextMenuItemVisual,
    action_bundle: impl Bundle,
) {
    let mut button = parent.spawn((
        Button,
        context_menu_button_node(style),
        BackgroundColor(context_menu_button_color(
            style,
            item.is_primary,
            item.is_disabled,
            Interaction::None,
        )),
        action_bundle,
    ));
    if item.is_disabled {
        button.insert(ContextMenuItemDisabled);
    }
    button.with_children(|button| {
        button.spawn((
            context_menu_button_label_node(),
            Text::new(item.label.clone()),
            TextFont::from_font_size(style.item_font_size).with_font(font.0.clone()),
            TextColor(context_menu_label_color(style, item.is_disabled)),
            TextLayout::new(style.text_justify, LineBreak::NoWrap),
            viewer_ui_passthrough_bundle(),
        ));
    });
}
