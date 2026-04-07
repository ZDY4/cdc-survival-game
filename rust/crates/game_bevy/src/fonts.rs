use bevy::prelude::{Assets, Font, Handle};

pub const GAME_UI_FONT_NAME: &str = "cdc_game_ui_cjk";

const GAME_UI_FONT_BYTES: &[u8] = include_bytes!("../assets/fonts/NotoSansCJKsc-Regular.otf");

pub fn game_ui_font_bytes() -> &'static [u8] {
    GAME_UI_FONT_BYTES
}

pub fn load_game_ui_font(fonts: &mut Assets<Font>) -> Handle<Font> {
    fonts.add(
        Font::try_from_bytes(GAME_UI_FONT_BYTES.to_vec())
            .expect("embedded UI font bytes should be a valid OpenType font"),
    )
}
