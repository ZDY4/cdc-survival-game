use std::collections::BTreeMap;

use game_data::{
    ActionPhase, ActionRequest, ActionType, ActorId, ActorSide, AttackHitKind, AttackOutcome,
    CharacterLootEntry, GridCoord, MapObjectDefinition, MapObjectFootprint, MapObjectKind,
    MapObjectProps, MapPickupProps, MapRotation,
};

use crate::movement::PendingProgressionStep;
use crate::vision::{has_grid_line_of_sight, DEFAULT_VISION_RADIUS};

use super::{Simulation, SimulationEvent};

const COMBAT_EXIT_NO_SIGHT_TURNS: u8 = 3;

impl Simulation {
    pub fn perform_attack(
        &mut self,
        actor_id: ActorId,
        target_actor: ActorId,
    ) -> game_data::ActionResult {
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
            cost_override: None,
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
            cost_override: None,
            success: true,
        });
        if result.success {
            let outcome = self.resolve_attack_outcome(actor_id, target_actor);
            self.events.push(SimulationEvent::AttackResolved {
                actor_id,
                target_actor,
                outcome: outcome.clone(),
            });
            if outcome.damage > 0.0 {
                self.apply_damage_to_actor(actor_id, target_actor, outcome.damage);
            }
            self.apply_attack_equipment_costs(actor_id);
        }
        result
    }

    pub fn set_combat_rng_seed(&mut self, seed: u64) {
        self.turn.combat_rng_seed = seed;
        self.turn.combat_rng_counter = 0;
    }

    pub fn enter_combat(&mut self, trigger_actor: ActorId, target_actor: ActorId) {
        self.enter_combat_internal(trigger_actor, target_actor, true);
    }

    pub(super) fn enter_combat_without_starting_turn(
        &mut self,
        trigger_actor: ActorId,
        target_actor: ActorId,
    ) {
        self.enter_combat_internal(trigger_actor, target_actor, false);
    }

    fn enter_combat_internal(
        &mut self,
        trigger_actor: ActorId,
        target_actor: ActorId,
        start_turn_if_needed: bool,
    ) {
        if !self.actors.contains(trigger_actor) {
            return;
        }

        if !self.turn.combat_active {
            self.turn.combat_active = true;
            self.turn.turns_without_hostile_player_sight = 0;
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

        if start_turn_if_needed
            && !self
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
            self.finish_combat_state_and_resume_exploration();
        }
    }

    pub(super) fn validate_attack_preconditions(
        &self,
        actor_id: ActorId,
        target_actor: ActorId,
    ) -> Result<(), &'static str> {
        self.validate_attack_target_spatial(actor_id, target_actor)?;

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

    fn resolve_attack_outcome(
        &mut self,
        actor_id: ActorId,
        target_actor: ActorId,
    ) -> AttackOutcome {
        let Some(current_hp) = self
            .actors
            .contains(target_actor)
            .then(|| self.actor_hit_points(target_actor))
        else {
            return AttackOutcome::default();
        };

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
        let actor_accuracy = self.actor_combat_attribute_value(actor_id, "accuracy")
            + self.actor_equipment_attribute_bonus(actor_id, "accuracy");
        let weapon_accuracy = weapon_profile
            .as_ref()
            .and_then(|weapon| weapon.accuracy)
            .map(|value| value as f32);
        let has_explicit_accuracy = actor_accuracy != 0.0 || weapon_accuracy.is_some();
        let hit_chance = if has_explicit_accuracy {
            ((actor_accuracy + weapon_accuracy.unwrap_or(0.0)) / 100.0).clamp(0.0, 1.0)
        } else {
            1.0
        };
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

        let hit_roll = self.next_combat_random_unit(actor_id.0 ^ target_actor.0.rotate_left(7));
        if hit_roll > hit_chance {
            return AttackOutcome {
                hit_kind: AttackHitKind::Miss,
                hit_chance,
                crit_chance,
                damage: 0.0,
                remaining_hp: current_hp,
                defeated: false,
            };
        }

        let base_damage = (attack_power.max(1.0) - defense).max(0.0);
        if base_damage <= 0.0 {
            return AttackOutcome {
                hit_kind: AttackHitKind::Blocked,
                hit_chance,
                crit_chance,
                damage: 0.0,
                remaining_hp: current_hp,
                defeated: false,
            };
        }

        let crit_roll =
            self.next_combat_random_unit(target_actor.0 ^ actor_id.0.rotate_left(13) ^ 0xC3A5_C85C);
        let is_crit = crit_roll <= crit_chance;
        let mut damage = base_damage * (1.0 - damage_reduction);
        if is_crit {
            damage *= crit_damage;
        }
        damage = damage.max(1.0).round();

        let remaining_hp = (current_hp - damage).max(0.0);
        AttackOutcome {
            hit_kind: if is_crit {
                AttackHitKind::Crit
            } else {
                AttackHitKind::Hit
            },
            hit_chance,
            crit_chance,
            damage,
            remaining_hp,
            defeated: remaining_hp <= 0.0,
        }
    }

    fn next_combat_random_unit(&mut self, salt: u64) -> f32 {
        let raw = splitmix64(
            self.turn.combat_rng_seed
                ^ self.turn.combat_rng_counter.rotate_left(17)
                ^ salt.rotate_left(29),
        );
        self.turn.combat_rng_counter = self.turn.combat_rng_counter.wrapping_add(1);
        (raw as f64 / u64::MAX as f64) as f32
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
        if self.exit_combat_if_resolved() {
            return;
        }
        if self.update_combat_visibility_decay() {
            return;
        }
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
        while self.turn.combat_active
            && self.turn.current_actor_id == Some(actor_id)
            && self.get_actor_ap(actor_id) >= self.config.affordable_threshold
        {
            if !self.execute_combat_ai_step(actor_id) && !self.execute_actor_turn_step(actor_id) {
                break;
            }
        }

        if self.turn.combat_active && self.turn.current_actor_id == Some(actor_id) {
            self.queue_pending_progression_once(PendingProgressionStep::EndCurrentCombatTurn);
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

    pub(super) fn first_player_seen_by_hostile(
        &self,
        hostile_actor_id: ActorId,
    ) -> Option<ActorId> {
        if self.get_actor_side(hostile_actor_id) != Some(ActorSide::Hostile) {
            return None;
        }

        self.actors.values().find_map(|actor| {
            (actor.side == ActorSide::Player
                && self.hostile_can_see_player(hostile_actor_id, actor.actor_id))
            .then_some(actor.actor_id)
        })
    }

    pub(super) fn hostile_player_visibility_pair(&self) -> Option<(ActorId, ActorId)> {
        self.actors.values().find_map(|actor| {
            (actor.side == ActorSide::Hostile)
                .then(|| self.first_player_seen_by_hostile(actor.actor_id))
                .flatten()
                .map(|player_id| (actor.actor_id, player_id))
        })
    }

    fn hostile_can_see_player(&self, hostile_actor_id: ActorId, player_actor_id: ActorId) -> bool {
        let Some(hostile_grid) = self.actor_grid_position(hostile_actor_id) else {
            return false;
        };
        let Some(player_grid) = self.actor_grid_position(player_actor_id) else {
            return false;
        };
        if hostile_grid.y != player_grid.y {
            return false;
        }

        let dx = i64::from(hostile_grid.x - player_grid.x);
        let dz = i64::from(hostile_grid.z - player_grid.z);
        let radius = i64::from(DEFAULT_VISION_RADIUS);
        if dx * dx + dz * dz > radius * radius {
            return false;
        }

        has_grid_line_of_sight(&self.grid_world, hostile_grid, player_grid)
    }

    pub(super) fn exit_combat_if_resolved(&mut self) -> bool {
        if !self.turn.combat_active {
            return false;
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
            return false;
        }

        self.finish_combat_state_and_resume_exploration();
        true
    }

    fn update_combat_visibility_decay(&mut self) -> bool {
        if self.hostile_player_visibility_pair().is_some() {
            self.turn.turns_without_hostile_player_sight = 0;
            return false;
        }

        self.turn.turns_without_hostile_player_sight = self
            .turn
            .turns_without_hostile_player_sight
            .saturating_add(1);
        if self.turn.turns_without_hostile_player_sight < COMBAT_EXIT_NO_SIGHT_TURNS {
            return false;
        }

        self.finish_combat_state_and_resume_exploration();
        true
    }

    fn finish_combat_state_and_resume_exploration(&mut self) {
        self.finish_combat_state();
        self.queue_pending_progression_once(PendingProgressionStep::StartNextNonCombatPlayerTurn);
    }

    fn finish_combat_state(&mut self) {
        self.turn.combat_active = false;
        self.turn.current_actor_id = None;
        self.turn.current_group_id = None;
        self.turn.combat_turn_index = 0;
        self.turn.turns_without_hostile_player_sight = 0;

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

fn splitmix64(mut state: u64) -> u64 {
    state = state.wrapping_add(0x9E37_79B9_7F4A_7C15);
    let mut z = state;
    z = (z ^ (z >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
    z = (z ^ (z >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
    z ^ (z >> 31)
}
