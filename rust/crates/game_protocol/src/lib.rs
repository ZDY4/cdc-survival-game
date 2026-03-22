mod messages;

use bevy_app::prelude::*;

pub use messages::{ClientMessage, ServerMessage};

pub struct GameProtocolPlugin;

impl Plugin for GameProtocolPlugin {
    fn build(&self, _app: &mut App) {}
}
