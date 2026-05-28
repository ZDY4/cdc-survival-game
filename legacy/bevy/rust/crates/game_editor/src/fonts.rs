use bevy::prelude::*;
use bevy_egui::EguiContexts;

pub use crate::preview::{
    game_ui_font_bytes, install_game_ui_fonts, load_game_ui_font, GAME_UI_FONT_NAME,
};

#[derive(Resource, Debug, Clone, Default)]
pub struct GameUiFontsState {
    pub initialized: bool,
}

pub fn configure_game_ui_fonts_system(
    mut contexts: EguiContexts,
    mut font_state: ResMut<GameUiFontsState>,
) {
    if font_state.initialized {
        return;
    }

    let Ok(ctx) = contexts.ctx_mut() else {
        return;
    };
    install_game_ui_fonts(ctx);
    font_state.initialized = true;
}
