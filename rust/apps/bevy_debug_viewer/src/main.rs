mod app;
mod bootstrap;
pub(crate) mod console;
mod controls;
mod dialogue;
mod game_ui;
mod geometry;
mod info_panels;
mod picking;
mod profiling;
mod render;
mod simulation;
mod state;
mod ui_context_menu;
#[cfg(test)]
mod test_support;

fn main() {
    app::run();
}
