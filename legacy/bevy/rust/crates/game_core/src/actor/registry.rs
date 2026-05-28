//! Actor 注册表模块。
//! 负责 actor 的增删查改和快照读写，不负责高层调度或 AI 行为选择。

use std::collections::HashMap;

use game_data::ActorId;

use super::{ActorRecord, ActorRegistrySnapshot};

#[derive(Debug, Default)]
pub struct ActorRegistry {
    actors: HashMap<ActorId, ActorRecord>,
}

impl ActorRegistry {
    pub fn insert(&mut self, actor: ActorRecord) {
        self.actors.insert(actor.actor_id, actor);
    }

    pub fn remove(&mut self, actor_id: ActorId) -> Option<ActorRecord> {
        self.actors.remove(&actor_id)
    }

    pub fn get(&self, actor_id: ActorId) -> Option<&ActorRecord> {
        self.actors.get(&actor_id)
    }

    pub fn get_mut(&mut self, actor_id: ActorId) -> Option<&mut ActorRecord> {
        self.actors.get_mut(&actor_id)
    }

    pub fn ids(&self) -> impl Iterator<Item = ActorId> + '_ {
        self.actors.keys().copied()
    }

    pub fn values(&self) -> impl Iterator<Item = &ActorRecord> {
        self.actors.values()
    }

    pub fn contains(&self, actor_id: ActorId) -> bool {
        self.actors.contains_key(&actor_id)
    }

    pub(crate) fn save_snapshot(&self) -> ActorRegistrySnapshot {
        let mut actors = self.values().cloned().collect::<Vec<_>>();
        actors.sort_by_key(|actor| actor.actor_id);
        ActorRegistrySnapshot { actors }
    }

    pub(crate) fn load_snapshot(&mut self, snapshot: ActorRegistrySnapshot) {
        self.actors = snapshot
            .actors
            .into_iter()
            .map(|actor| (actor.actor_id, actor))
            .collect();
    }
}
