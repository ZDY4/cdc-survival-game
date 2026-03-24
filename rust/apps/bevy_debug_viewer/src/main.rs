mod app;
mod bootstrap;
mod controls;
mod dialogue;
mod geometry;
mod hud;
mod render;
mod simulation;
mod state;
#[cfg(test)]
mod test_support;

fn main() {
    app::run();
}
