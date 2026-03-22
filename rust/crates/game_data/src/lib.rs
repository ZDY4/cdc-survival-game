pub mod content;
pub mod models;

use bevy_app::prelude::*;

pub use content::{
    ArmorData, ConsumableData, DialogueAction, DialogueConnection, DialogueData, DialogueNode,
    DialogueOption, DialoguePosition, ItemData, WeaponData,
};
pub use models::{
    ActionPhase, ActionRequest, ActionResult, ActionType, ActorId, ActorKind, ActorSide, GridCoord,
    TurnState, WorldCoord,
};

pub struct GameDataPlugin;

impl Plugin for GameDataPlugin {
    fn build(&self, _app: &mut App) {}
}
