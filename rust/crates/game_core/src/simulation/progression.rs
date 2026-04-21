use std::collections::{BTreeMap, BTreeSet};

use game_data::{ActorId, QuestNode};

use super::{ActorProgressionState, QuestRuntimeState, Simulation, SimulationEvent};

impl Simulation {
    pub fn active_quest_states_for_actor(&self, actor_id: ActorId) -> Vec<QuestRuntimeState> {
        let mut quests = self
            .active_quests
            .values()
            .filter(|state| state.owner_actor_id == actor_id)
            .cloned()
            .collect::<Vec<_>>();
        quests.sort_by(|left, right| left.quest_id.cmp(&right.quest_id));
        quests
    }

    pub fn start_quest(&mut self, actor_id: ActorId, quest_id: &str) -> bool {
        if !self.actors.contains(actor_id) {
            return false;
        }
        let Some((prerequisites, start_node_id)) = self
            .quest_library
            .as_ref()
            .and_then(|library| library.get(quest_id))
            .map(|quest| {
                (
                    quest.prerequisites.clone(),
                    quest.flow.start_node_id.clone(),
                )
            })
        else {
            return false;
        };
        if self.active_quests.contains_key(quest_id) || self.completed_quests.contains(quest_id) {
            return false;
        }
        if prerequisites
            .iter()
            .any(|prerequisite| !self.completed_quests.contains(prerequisite))
        {
            return false;
        }

        self.active_quests.insert(
            quest_id.to_string(),
            QuestRuntimeState {
                quest_id: quest_id.to_string(),
                owner_actor_id: actor_id,
                current_node_id: start_node_id,
                completed_objectives: BTreeMap::new(),
                granted_reward_nodes: BTreeSet::new(),
            },
        );
        self.events.push(SimulationEvent::QuestStarted {
            actor_id,
            quest_id: quest_id.to_string(),
        });
        self.advance_active_quest(quest_id);
        true
    }

    pub fn turn_in_active_quest(
        &mut self,
        actor_id: ActorId,
        quest_id: &str,
    ) -> Result<(), String> {
        let Some(state) = self.active_quests.get(quest_id) else {
            return Err(format!("quest_not_active:{quest_id}"));
        };
        if state.owner_actor_id != actor_id {
            return Err(format!("quest_owner_mismatch:{quest_id}"));
        }

        let Some(node) = self.current_active_quest_node(quest_id).cloned() else {
            return Err(format!("quest_node_missing:{quest_id}"));
        };
        if node.node_type != "objective" || !quest_node_requires_manual_turn_in(&node) {
            return Err(format!("quest_not_waiting_for_turn_in:{quest_id}"));
        }

        let current = state
            .completed_objectives
            .get(&node.id)
            .copied()
            .unwrap_or(0);
        if current < objective_target(&node) {
            return Err(format!("quest_objective_incomplete:{quest_id}"));
        }

        if let Some(item_id) = node.item_id {
            self.economy
                .remove_item(actor_id, item_id, objective_target(&node))
                .map_err(|error| error.to_string())?;
        }

        if !self.advance_quest_to_connection(quest_id, &node.id, 0) {
            return Err(format!(
                "quest_turn_in_connection_missing:{quest_id}:{}",
                node.id
            ));
        }
        self.advance_active_quest(quest_id);
        Ok(())
    }

    pub fn seed_actor_progression(&mut self, actor_id: ActorId, level: i32, xp_reward: i32) {
        if !self.actors.contains(actor_id) {
            return;
        }
        let normalized_level = level.max(1);
        self.actor_progression.insert(
            actor_id,
            ActorProgressionState {
                level: normalized_level,
                ..ActorProgressionState::default()
            },
        );
        self.actor_xp_rewards.insert(actor_id, xp_reward.max(0));
        self.economy.set_actor_level(actor_id, normalized_level);
    }

    pub fn actor_level(&self, actor_id: ActorId) -> i32 {
        self.actor_progression
            .get(&actor_id)
            .map(|state| state.level.max(1))
            .unwrap_or(1)
    }

    pub fn actor_current_xp(&self, actor_id: ActorId) -> i32 {
        self.actor_progression
            .get(&actor_id)
            .map(|state| state.current_xp.max(0))
            .unwrap_or(0)
    }

    pub fn allocate_attribute_point(
        &mut self,
        actor_id: ActorId,
        attribute: &str,
    ) -> Result<i32, String> {
        let normalized = attribute.trim().to_ascii_lowercase();
        if normalized.is_empty() {
            return Err("attribute_missing".to_string());
        }

        let progression = self
            .actor_progression
            .get_mut(&actor_id)
            .ok_or_else(|| format!("unknown_actor:{actor_id:?}"))?;
        if progression.available_stat_points <= 0 {
            return Err("attribute_points_unavailable".to_string());
        }

        let current = self
            .economy
            .actor(actor_id)
            .and_then(|actor| actor.attributes.get(&normalized))
            .copied()
            .unwrap_or(0);
        progression.available_stat_points -= 1;
        self.economy
            .set_actor_attribute(actor_id, normalized.clone(), current + 1);
        Ok(current + 1)
    }

    pub(super) fn award_kill_experience(&mut self, actor_id: ActorId, target_actor: ActorId) {
        if !self.actors.contains(actor_id) {
            return;
        }
        let amount = self
            .actor_xp_rewards
            .get(&target_actor)
            .copied()
            .unwrap_or(0)
            .max(0);
        self.grant_experience(actor_id, amount);
    }

    pub(super) fn advance_kill_quest_progress(&mut self, actor_id: ActorId, target_actor: ActorId) {
        let enemy_type = self
            .actors
            .get(target_actor)
            .and_then(|actor| actor.definition_id.as_ref())
            .map(|definition_id| derive_enemy_type(definition_id.as_str()))
            .unwrap_or_default();
        self.advance_objective_progress(actor_id, "kill", 1, Some(0), Some(enemy_type), None);
    }

    pub(super) fn advance_collect_quest_progress(
        &mut self,
        actor_id: ActorId,
        item_id: u32,
        count: i32,
    ) {
        self.advance_objective_progress(
            actor_id,
            "collect",
            count.max(1),
            Some(item_id),
            None,
            None,
        );
    }

    fn advance_objective_progress(
        &mut self,
        actor_id: ActorId,
        objective_type: &str,
        amount: i32,
        item_id: Option<u32>,
        enemy_type: Option<String>,
        target_location: Option<String>,
    ) {
        let quest_ids: Vec<String> = self
            .active_quests
            .iter()
            .filter(|(_, state)| state.owner_actor_id == actor_id)
            .map(|(quest_id, _)| quest_id.clone())
            .collect();

        for quest_id in quest_ids {
            let progress = {
                let Some(node) = self.current_active_quest_node(&quest_id).cloned() else {
                    continue;
                };
                if node.node_type != "objective" || node.objective_type != objective_type {
                    continue;
                }
                if let Some(expected_item_id) = node.item_id {
                    if item_id != Some(expected_item_id) {
                        continue;
                    }
                }
                if let Some(expected_enemy_type) = node
                    .extra
                    .get("enemy_type")
                    .and_then(|value| value.as_str())
                {
                    if enemy_type.as_deref() != Some(expected_enemy_type) {
                        continue;
                    }
                }
                if !target_location_matches(&node, target_location.as_deref()) {
                    continue;
                }

                let target = objective_target(&node);
                let state = self
                    .active_quests
                    .get_mut(&quest_id)
                    .expect("quest should exist");
                let current = state
                    .completed_objectives
                    .get(&node.id)
                    .copied()
                    .unwrap_or(0);
                let next = (current + amount).clamp(0, target);
                if next == current {
                    continue;
                }
                state.completed_objectives.insert(node.id.clone(), next);
                Some((node.id.clone(), next, target))
            };

            let Some((node_id, current, target)) = progress else {
                continue;
            };
            self.events.push(SimulationEvent::QuestObjectiveProgressed {
                actor_id,
                quest_id: quest_id.clone(),
                node_id: node_id.clone(),
                current,
                target,
            });
            if current >= target {
                self.advance_active_quest(&quest_id);
            }
        }
    }

    fn advance_active_quest(&mut self, quest_id: &str) {
        loop {
            let Some(node) = self.current_active_quest_node(quest_id).cloned() else {
                return;
            };
            match node.node_type.as_str() {
                "start" => {
                    if !self.advance_quest_to_connection(quest_id, &node.id, 0) {
                        return;
                    }
                }
                "objective" => {
                    let current = self
                        .active_quests
                        .get(quest_id)
                        .and_then(|state| state.completed_objectives.get(&node.id).copied())
                        .unwrap_or(0);
                    if current < objective_target(&node) {
                        return;
                    }
                    if quest_node_requires_manual_turn_in(&node) {
                        return;
                    }
                    if !self.advance_quest_to_connection(quest_id, &node.id, 0) {
                        return;
                    }
                }
                "reward" => {
                    self.grant_quest_reward_node(quest_id, &node);
                    if !self.advance_quest_to_connection(quest_id, &node.id, 0) {
                        return;
                    }
                }
                "end" => {
                    let Some(state) = self.active_quests.remove(quest_id) else {
                        return;
                    };
                    self.completed_quests.insert(quest_id.to_string());
                    self.events.push(SimulationEvent::QuestCompleted {
                        actor_id: state.owner_actor_id,
                        quest_id: quest_id.to_string(),
                    });
                    return;
                }
                _ => return,
            }
        }
    }

    fn advance_quest_to_connection(
        &mut self,
        quest_id: &str,
        from_node_id: &str,
        from_port: i32,
    ) -> bool {
        let Some(next_node_id) = self
            .quest_library
            .as_ref()
            .and_then(|library| library.get(quest_id))
            .and_then(|quest| {
                quest.flow.connections.iter().find_map(|connection| {
                    (connection.from == from_node_id && connection.from_port == from_port)
                        .then(|| connection.to.clone())
                })
            })
        else {
            return false;
        };

        let Some(state) = self.active_quests.get_mut(quest_id) else {
            return false;
        };
        state.current_node_id = next_node_id;
        true
    }

    fn current_active_quest_node(&self, quest_id: &str) -> Option<&QuestNode> {
        let state = self.active_quests.get(quest_id)?;
        let quest = self.quest_library.as_ref()?.get(quest_id)?;
        quest.flow.nodes.get(&state.current_node_id)
    }

    fn grant_quest_reward_node(&mut self, quest_id: &str, node: &QuestNode) {
        let actor_id = {
            let Some(state) = self.active_quests.get_mut(quest_id) else {
                return;
            };
            if !state.granted_reward_nodes.insert(node.id.clone()) {
                return;
            }
            state.owner_actor_id
        };
        for reward_item in &node.rewards.items {
            if reward_item.id == 0 || reward_item.count <= 0 {
                continue;
            }
            if let Some(items) = self.item_library.as_ref() {
                let _ = self
                    .economy
                    .add_item(actor_id, reward_item.id, reward_item.count, items);
            } else {
                let _ =
                    self.economy
                        .add_item_unchecked(actor_id, reward_item.id, reward_item.count);
            }
        }
        if node.rewards.experience > 0 {
            self.grant_experience(actor_id, node.rewards.experience);
        }
        if node.rewards.skill_points > 0 {
            let _ = self
                .economy
                .add_skill_points(actor_id, node.rewards.skill_points);
            if let Some(progression) = self.actor_progression.get_mut(&actor_id) {
                progression.available_skill_points += node.rewards.skill_points;
                progression.total_skill_points_earned += node.rewards.skill_points;
            }
        }
        if let Some(recipes) = self.recipe_library.as_ref() {
            for recipe_id in &node.rewards.unlock_recipes {
                let _ = self
                    .economy
                    .unlock_recipe(actor_id, recipe_id.clone(), recipes);
            }
        }
    }

    fn grant_experience(&mut self, actor_id: ActorId, amount: i32) {
        if amount <= 0 || !self.actors.contains(actor_id) {
            return;
        }

        let (total_xp_after, level_up_event) = {
            let state = self.actor_progression.entry(actor_id).or_insert_with(|| {
                let level = self
                    .economy
                    .actor(actor_id)
                    .map(|actor| actor.level)
                    .unwrap_or(1)
                    .max(1);
                ActorProgressionState {
                    level,
                    ..ActorProgressionState::default()
                }
            });
            state.current_xp += amount;
            state.total_xp_earned += amount;
            let mut level_up_event = None;

            while state.current_xp >= xp_to_next_level(state.level) {
                let required = xp_to_next_level(state.level);
                state.current_xp -= required;
                state.level += 1;
                state.available_stat_points += 3;
                state.available_skill_points += 1;
                state.total_stat_points_earned += 3;
                state.total_skill_points_earned += 1;
                let _ = self.economy.add_skill_points(actor_id, 1);
                level_up_event = Some((
                    state.level,
                    state.available_stat_points,
                    state.available_skill_points,
                ));
            }
            let total_xp_after = state.current_xp;
            self.economy.set_actor_level(actor_id, state.level);
            (total_xp_after, level_up_event)
        };

        self.events.push(SimulationEvent::ExperienceGranted {
            actor_id,
            amount,
            total_xp: total_xp_after,
        });
        if let Some((new_level, available_stat_points, available_skill_points)) = level_up_event {
            self.events.push(SimulationEvent::ActorLeveledUp {
                actor_id,
                new_level,
                available_stat_points,
                available_skill_points,
            });
        }
    }
}

fn xp_to_next_level(level: i32) -> i32 {
    let normalized_level = level.max(1) as f32;
    (100.0 * normalized_level.powf(1.2)).round() as i32
}

fn objective_target(node: &QuestNode) -> i32 {
    node.count.max(1)
}

fn quest_node_requires_manual_turn_in(node: &QuestNode) -> bool {
    node.extra
        .get("manual_turn_in")
        .and_then(|value| value.as_bool())
        .unwrap_or(false)
}

fn target_location_matches(node: &QuestNode, provided_location: Option<&str>) -> bool {
    let expected = node.target.trim();
    expected.is_empty() || provided_location == Some(expected)
}

fn derive_enemy_type(definition_id: &str) -> String {
    definition_id
        .split('_')
        .next()
        .unwrap_or_default()
        .to_string()
}
