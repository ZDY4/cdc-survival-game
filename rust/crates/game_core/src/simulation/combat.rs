use super::*;

impl Simulation {
    pub fn perform_attack(&mut self, actor_id: ActorId, target_actor: ActorId) -> ActionResult {
        if !self.actors.contains(target_actor) {
            return self.reject_action("unknown_target", actor_id);
        }
        if let Err(reason) = self.validate_attack_preconditions(actor_id, target_actor) {
            return self.reject_action(reason, actor_id);
        }

        let start_result = self.request_action(ActionRequest {
            actor_id,
            action_type: ActionType::Attack,
            phase: ActionPhase::Start,
            steps: None,
            target_actor: Some(target_actor),
            success: true,
        });
        if !start_result.success {
            return start_result;
        }

        let result = self.request_action(ActionRequest {
            actor_id,
            action_type: ActionType::Attack,
            phase: ActionPhase::Complete,
            steps: None,
            target_actor: Some(target_actor),
            success: true,
        });
        if result.success {
            self.apply_attack_damage(actor_id, target_actor);
            self.apply_attack_equipment_costs(actor_id);
        }
        result
    }

    pub fn enter_combat(&mut self, trigger_actor: ActorId, target_actor: ActorId) {
        if !self.actors.contains(trigger_actor) {
            return;
        }

        if !self.turn.combat_active {
            self.turn.combat_active = true;
            let actor_ids: Vec<ActorId> = self.actors.ids().collect();
            for actor_id in actor_ids {
                if let Some(actor) = self.actors.get_mut(actor_id) {
                    actor.in_combat = true;
                }
            }
            self.events
                .push(SimulationEvent::CombatStateChanged { in_combat: true });
        }

        self.turn.current_actor_id = Some(trigger_actor);
        self.turn.current_group_id = self
            .actors
            .get(trigger_actor)
            .map(|actor| actor.group_id.clone());

        if let Some(target) = self.actors.get_mut(target_actor) {
            target.in_combat = true;
        }

        if !self
            .actors
            .get(trigger_actor)
            .map(|actor| actor.turn_open)
            .unwrap_or(false)
        {
            self.start_actor_turn(trigger_actor);
        }
    }

    pub fn force_end_combat(&mut self) {
        if self.turn.combat_active {
            self.finish_combat_state();
        }
    }

    pub(super) fn validate_attack_preconditions(
        &self,
        actor_id: ActorId,
        target_actor: ActorId,
    ) -> Result<(), &'static str> {
        let Some(actor_grid) = self.actor_grid_position(actor_id) else {
            return Err("unknown_actor");
        };
        let Some(target_grid) = self.actor_grid_position(target_actor) else {
            return Err("unknown_target");
        };
        if !self.is_interaction_in_range(
            actor_grid,
            target_grid,
            self.attack_interaction_distance(actor_id),
        ) {
            return Err("target_out_of_range");
        }

        let Some(items) = self.item_library.as_ref() else {
            return Ok(());
        };
        let Ok(Some(weapon)) = self.economy.equipped_weapon(actor_id, "main_hand", items) else {
            return Ok(());
        };
        if weapon.ammo_type.is_some() && weapon.max_ammo.unwrap_or(0) > 0 && weapon.ammo_loaded <= 0
        {
            return Err("weapon_unloaded");
        }

        Ok(())
    }

    fn apply_attack_equipment_costs(&mut self, actor_id: ActorId) {
        let Some(items) = self.item_library.as_ref().cloned() else {
            return;
        };
        let Ok(Some(weapon)) = self.economy.equipped_weapon(actor_id, "main_hand", &items) else {
            return;
        };

        if weapon.ammo_type.is_some() && weapon.max_ammo.unwrap_or(0) > 0 {
            let _ = self
                .economy
                .consume_equipped_ammo(actor_id, "main_hand", 1, &items);
        }
        if weapon.current_durability.is_some() {
            let _ = self
                .economy
                .consume_equipped_durability(actor_id, "main_hand", 1);
        }
    }

    fn apply_attack_damage(&mut self, actor_id: ActorId, target_actor: ActorId) {
        if !self.actors.contains(target_actor) {
            return;
        }

        let damage = self.resolve_attack_damage(actor_id, target_actor);
        self.apply_damage_to_actor(actor_id, target_actor, damage);
    }

    fn resolve_attack_damage(&self, actor_id: ActorId, target_actor: ActorId) -> f32 {
        let weapon_profile = self
            .item_library
            .as_ref()
            .and_then(|items| {
                self.economy
                    .equipped_weapon(actor_id, "main_hand", items)
                    .ok()
            })
            .flatten();
        let attack_power = self.actor_combat_attribute_value(actor_id, "attack_power")
            + self.actor_equipment_attribute_bonus(actor_id, "attack_power")
            + weapon_profile
                .as_ref()
                .map(|weapon| weapon.damage.max(0) as f32)
                .unwrap_or(0.0);
        let accuracy = self.actor_combat_attribute_value(actor_id, "accuracy")
            + self.actor_equipment_attribute_bonus(actor_id, "accuracy")
            + weapon_profile
                .as_ref()
                .and_then(|weapon| weapon.accuracy)
                .map(|value| value as f32)
                .unwrap_or(0.0);
        let crit_chance = (self.actor_combat_attribute_value(actor_id, "crit_chance")
            + self.actor_equipment_attribute_bonus(actor_id, "crit_chance")
            + weapon_profile
                .as_ref()
                .map(|weapon| weapon.crit_chance)
                .unwrap_or(0.0))
        .clamp(0.0, 1.0);
        let crit_damage = weapon_profile
            .as_ref()
            .map(|weapon| weapon.crit_multiplier.max(1.0))
            .unwrap_or_else(|| {
                self.actor_combat_attribute_value(actor_id, "crit_damage")
                    .max(1.0)
            });

        let defense = (self.actor_combat_attribute_value(target_actor, "defense")
            + self.actor_equipment_attribute_bonus(target_actor, "defense"))
        .max(0.0);
        let damage_reduction = self
            .actor_combat_attribute_value(target_actor, "damage_reduction")
            .clamp(0.0, 0.95);
        let accuracy_multiplier = (accuracy / 100.0).clamp(0.25, 1.5);
        let crit_multiplier = 1.0 + crit_chance * (crit_damage - 1.0);

        let mut damage =
            ((attack_power.max(1.0) * accuracy_multiplier * crit_multiplier) - defense).max(1.0);
        damage *= 1.0 - damage_reduction;
        damage.max(1.0).round()
    }

    fn spawn_loot_drops(&mut self, actor_id: ActorId, target_actor: ActorId, grid: GridCoord) {
        let Some(loot_entries) = self.actor_loot_tables.get(&target_actor).cloned() else {
            return;
        };

        for entry in loot_entries {
            let count = self.resolve_loot_drop_count(target_actor, &entry);
            if count <= 0 {
                continue;
            }

            let object_id = format!(
                "loot_{}_{}_{}",
                target_actor.0,
                entry.item_id,
                self.events.len()
            );
            self.grid_world.upsert_map_object(MapObjectDefinition {
                object_id: object_id.clone(),
                kind: MapObjectKind::Pickup,
                anchor: grid,
                footprint: MapObjectFootprint::default(),
                rotation: MapRotation::North,
                blocks_movement: false,
                blocks_sight: false,
                props: MapObjectProps {
                    pickup: Some(MapPickupProps {
                        item_id: entry.item_id.to_string(),
                        min_count: count,
                        max_count: count,
                        extra: BTreeMap::new(),
                    }),
                    ..MapObjectProps::default()
                },
            });
            self.events.push(SimulationEvent::LootDropped {
                actor_id,
                target_actor,
                object_id,
                item_id: entry.item_id,
                count,
                grid,
            });
        }
    }

    fn resolve_loot_drop_count(&self, target_actor: ActorId, entry: &CharacterLootEntry) -> i32 {
        if entry.max < entry.min || entry.max <= 0 || entry.chance <= 0.0 {
            return 0;
        }

        let roll_seed = target_actor.0 ^ (entry.item_id as u64).wrapping_mul(1_103_515_245);
        let chance_roll = (roll_seed % 10_000) as f32 / 10_000.0;
        if chance_roll > entry.chance {
            return 0;
        }

        let span = (entry.max - entry.min).max(0) as u64;
        let count_roll = ((roll_seed / 97) % (span + 1)) as i32;
        (entry.min + count_roll).max(0)
    }

    pub(super) fn end_current_combat_turn(&mut self) {
        let Some(current_actor) = self.turn.current_actor_id else {
            return;
        };

        self.end_actor_turn(current_actor);
        self.exit_combat_if_resolved();
        if self.turn.combat_active {
            self.select_next_combat_actor();
        }
    }

    fn select_next_combat_actor(&mut self) {
        let ordered_groups = self.sorted_group_ids();
        if ordered_groups.is_empty() {
            return;
        }

        let current_group = self.turn.current_group_id.clone().unwrap_or_default();
        let start_group_index = ordered_groups
            .iter()
            .position(|group_id| *group_id == current_group)
            .unwrap_or(0);
        let current_actor = self.turn.current_actor_id;

        let Some((group_id, actor_id)) =
            self.find_next_combat_actor(&ordered_groups, start_group_index, current_actor)
        else {
            return;
        };

        self.turn.current_group_id = Some(group_id);
        self.turn.current_actor_id = Some(actor_id);
        self.turn.combat_turn_index += 1;
        self.start_actor_turn(actor_id);
    }

    pub(super) fn run_combat_ai_turn(&mut self, actor_id: ActorId) {
        if !self.ai_controllers.contains_key(&actor_id) {
            return;
        }

        while self.turn.combat_active
            && self.turn.current_actor_id == Some(actor_id)
            && self.get_actor_ap(actor_id) >= self.config.affordable_threshold
        {
            if !self.execute_actor_turn_step(actor_id) {
                break;
            }
        }

        if self.turn.combat_active && self.turn.current_actor_id == Some(actor_id) {
            if self.pending_progression.back()
                != Some(&PendingProgressionStep::EndCurrentCombatTurn)
            {
                self.queue_pending_progression(PendingProgressionStep::EndCurrentCombatTurn);
            }
        }
    }

    fn find_next_combat_actor(
        &self,
        ordered_groups: &[String],
        start_group_index: usize,
        current_actor: Option<ActorId>,
    ) -> Option<(String, ActorId)> {
        if ordered_groups.is_empty() {
            return None;
        }

        let current_group = ordered_groups.get(start_group_index)?;
        if let Some(current_actor) = current_actor {
            let actor_ids = self.group_actor_ids(current_group);
            if let Some(actor_index) = actor_ids
                .iter()
                .position(|candidate| *candidate == current_actor)
            {
                for idx in (actor_index + 1)..actor_ids.len() {
                    return Some((current_group.clone(), actor_ids[idx]));
                }
            }
        }

        for offset in 1..=ordered_groups.len() {
            let group_index = (start_group_index + offset) % ordered_groups.len();
            let group_id = &ordered_groups[group_index];
            let actor_ids = self.group_actor_ids(group_id);
            if let Some(first_actor) = actor_ids.first().copied() {
                return Some((group_id.clone(), first_actor));
            }
        }

        None
    }

    pub(super) fn apply_damage_to_actor(
        &mut self,
        actor_id: ActorId,
        target_actor: ActorId,
        damage: f32,
    ) {
        if !self.actors.contains(target_actor) {
            return;
        }

        let current_hp = self.actor_hit_points(target_actor);
        let next_hp = (current_hp - damage).max(0.0);
        let defeat_position = self.actor_grid_position(target_actor);
        self.actor_resources
            .entry(target_actor)
            .or_default()
            .insert("hp".to_string(), next_hp);
        self.events.push(SimulationEvent::ActorDamaged {
            actor_id,
            target_actor,
            damage,
            remaining_hp: next_hp,
        });

        if next_hp <= 0.0 {
            self.award_kill_experience(actor_id, target_actor);
            self.advance_kill_quest_progress(actor_id, target_actor);
            self.events.push(SimulationEvent::ActorDefeated {
                actor_id,
                target_actor,
            });
            if let Some(grid) = defeat_position {
                self.spawn_loot_drops(actor_id, target_actor, grid);
            }
            self.unregister_actor(target_actor);
        }
    }

    pub(super) fn exit_combat_if_resolved(&mut self) {
        if !self.turn.combat_active {
            return;
        }

        let mut friendly_count = 0usize;
        let mut hostile_count = 0usize;
        for actor in self.actors.values() {
            match actor.side {
                ActorSide::Hostile => hostile_count += 1,
                ActorSide::Player | ActorSide::Friendly => friendly_count += 1,
                ActorSide::Neutral => {}
            }
        }

        if hostile_count > 0 && friendly_count > 0 {
            return;
        }

        self.finish_combat_state();
    }

    fn finish_combat_state(&mut self) {
        self.turn.combat_active = false;
        self.turn.current_actor_id = None;
        self.turn.current_group_id = None;
        self.turn.combat_turn_index = 0;

        let actor_ids: Vec<ActorId> = self.actors.ids().collect();
        for actor_id in actor_ids {
            if let Some(actor) = self.actors.get_mut(actor_id) {
                actor.in_combat = false;
                actor.turn_open = false;
            }
        }

        self.events
            .push(SimulationEvent::CombatStateChanged { in_combat: false });
    }
}
