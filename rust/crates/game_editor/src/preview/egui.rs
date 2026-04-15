use bevy::prelude::{Assets, Font, Handle};
use bevy_egui::egui;

pub const GAME_UI_FONT_NAME: &str = "cdc_game_ui_cjk";

const GAME_UI_FONT_BYTES: &[u8] =
    include_bytes!("../../../../../assets/fonts/NotoSansCJKsc-Regular.otf");

pub fn game_ui_font_bytes() -> &'static [u8] {
    GAME_UI_FONT_BYTES
}

pub fn load_game_ui_font(fonts: &mut Assets<Font>) -> Handle<Font> {
    fonts.add(
        Font::try_from_bytes(GAME_UI_FONT_BYTES.to_vec())
            .expect("embedded UI font bytes should be a valid OpenType font"),
    )
}

pub fn install_game_ui_fonts(ctx: &egui::Context) {
    let mut fonts = egui::FontDefinitions::default();
    fonts.font_data.insert(
        GAME_UI_FONT_NAME.to_string(),
        egui::FontData::from_owned(game_ui_font_bytes().to_vec()).into(),
    );
    for family in [egui::FontFamily::Proportional, egui::FontFamily::Monospace] {
        fonts
            .families
            .entry(family)
            .or_default()
            .insert(0, GAME_UI_FONT_NAME.to_string());
    }
    ctx.set_fonts(fonts);
}
