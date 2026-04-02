use bevy::prelude::{Color, Interaction};

pub(crate) fn hud_tab_button_color(selected: bool, interaction: Interaction) -> Color {
    match (selected, interaction) {
        (true, Interaction::Pressed) => Color::srgba(0.26, 0.4, 0.58, 0.98),
        (true, Interaction::Hovered) => Color::srgba(0.22, 0.35, 0.5, 0.98),
        (true, Interaction::None) => Color::srgba(0.18, 0.3, 0.45, 0.96),
        (false, Interaction::Pressed) => Color::srgba(0.23, 0.27, 0.33, 0.98),
        (false, Interaction::Hovered) => Color::srgba(0.17, 0.2, 0.26, 0.96),
        (false, Interaction::None) => Color::srgba(0.11, 0.13, 0.17, 0.94),
    }
}

pub(crate) fn hud_tab_button_border_color(selected: bool) -> Color {
    if selected {
        Color::srgba(0.52, 0.74, 0.98, 1.0)
    } else {
        Color::srgba(0.19, 0.24, 0.32, 1.0)
    }
}

#[cfg(test)]
mod tests {
    use super::hud_tab_button_color;
    use bevy::prelude::Interaction;

    #[test]
    fn tab_button_colors_vary_with_selection_and_interaction() {
        let selected = hud_tab_button_color(true, Interaction::None).to_srgba();
        let unselected = hud_tab_button_color(false, Interaction::None).to_srgba();
        assert_ne!(selected, unselected);
    }
}
