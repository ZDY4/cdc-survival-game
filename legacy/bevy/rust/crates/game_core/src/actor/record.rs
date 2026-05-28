//! Actor 记录定义模块。
//! 负责运行时 actor 基础记录和快照结构，不负责注册表操作或 AI 控制。

use game_data::{ActorId, ActorKind, ActorSide, CharacterId, GridCoord};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ActorRecord {
    pub actor_id: ActorId,
    pub definition_id: Option<CharacterId>,
    pub display_name: String,
    pub kind: ActorKind,
    pub side: ActorSide,
    pub group_id: String,
    pub registration_index: usize,
    pub ap: f32,
    pub turn_open: bool,
    pub in_combat: bool,
    pub grid_position: GridCoord,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub(crate) struct ActorRegistrySnapshot {
    pub actors: Vec<ActorRecord>,
}
