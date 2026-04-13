use std::collections::HashMap;
use std::collections::VecDeque;
use std::collections::{BTreeMap, BTreeSet};

use game_data::{
    ActionPhase, ActionRequest, ActionResult, ActionType, ActorId, ActorSide, CharacterId,
    CharacterInteractionProfile, CharacterLootEntry, CharacterResourcePool, DialogueAction,
    DialogueLibrary, DialogueRuleLibrary, DialogueSessionState, GridCoord,
    InteractionContextSnapshot, InteractionTargetId, ItemLibrary, MapLibrary, MapObjectDefinition,
    OverworldDefinition, OverworldLibrary, QuestLibrary, RecipeLibrary, ShopLibrary, SkillLibrary,
    TurnState, WorldCoord, WorldMode,
};
use tracing::info;

use crate::actor::{ActorRecord, ActorRegistry, RuntimeAiController};
use crate::economy::HeadlessEconomyRuntime;
use crate::goap::{NpcActionKey, NpcBackgroundState, NpcRuntimeActionState};
use crate::grid::{find_path_grid, find_path_world, GridPathfindingError, GridWorld};
use crate::movement::{
    MovementCommandOutcome, MovementPlan, MovementPlanError, PendingProgressionStep,
};
use crate::overworld::{compute_cell_path, resolve_overworld_goal, UnlockedLocationSet};
use crate::runtime::DropItemOutcome;
use crate::turn::{ActiveActions, GroupOrderRegistry, TurnConfig, TurnRuntime};

mod actions;
mod combat;
mod combat_ai;
mod dialogue;
pub(crate) mod interaction_behaviors;
mod interaction_flow;
mod level_transition;
mod overworld;
mod progression;
mod skills;
mod snapshot;
mod spatial;
mod state_persistence;
mod state_queries;
mod types;

const DROP_ITEM_SEARCH_RADIUS: i32 = 4;

pub(crate) use self::state_persistence::SimulationStateSnapshot;
pub use self::combat_ai::{
    resolve_combat_tactic_profile_id, select_combat_ai_intent_for_profile,
    select_default_combat_ai_intent, CombatAiExecutionResult, CombatAiIntent, CombatAiSnapshot,
    CombatSkillOption, CombatTargetOption,
};
pub use self::types::{
    ActorDebugState, ActorProgressionState, AttackTargetingQueryResult, CombatDebugState,
    GridDebugState, MapCellDebugState, MapObjectDebugState, QuestRuntimeState, RegisterActor,
    SimulationCommand, SimulationCommandResult, SimulationEvent, SimulationSnapshot,
    SkillActivationResult, SkillRuntimeState, SkillSpatialPreviewResult, SkillTargetingQueryResult,
};

#[derive(Debug)]
pub struct Simulation {
    config: TurnConfig,
    turn: TurnRuntime,
    group_orders: GroupOrderRegistry,
    active_actions: ActiveActions,
    actors: ActorRegistry,
    actor_interactions: HashMap<ActorId, CharacterInteractionProfile>,
    actor_attack_ranges: HashMap<ActorId, f32>,
    actor_combat_attributes: HashMap<ActorId, BTreeMap<String, f32>>,
    actor_resources: HashMap<ActorId, BTreeMap<String, f32>>,
    actor_loot_tables: HashMap<ActorId, Vec<CharacterLootEntry>>,
    actor_progression: HashMap<ActorId, ActorProgressionState>,
    actor_xp_rewards: HashMap<ActorId, i32>,
    actor_skill_states: HashMap<ActorId, BTreeMap<String, SkillRuntimeState>>,
    quest_library: Option<QuestLibrary>,
    skill_library: Option<SkillLibrary>,
    recipe_library: Option<RecipeLibrary>,
    shop_library: Option<ShopLibrary>,
    dialogue_library: Option<DialogueLibrary>,
    dialogue_rule_library: Option<DialogueRuleLibrary>,
    active_quests: BTreeMap<String, QuestRuntimeState>,
    completed_quests: BTreeSet<String>,
    actor_relationships: HashMap<(ActorId, ActorId), i32>,
    actor_autonomous_movement_goals: HashMap<ActorId, GridCoord>,
    active_dialogues: HashMap<ActorId, DialogueSessionState>,
    actor_runtime_actions: HashMap<ActorId, NpcRuntimeActionState>,
    economy: HeadlessEconomyRuntime,
    item_library: Option<ItemLibrary>,
    map_library: Option<MapLibrary>,
    overworld_library: Option<OverworldLibrary>,
    interaction_context: InteractionContextSnapshot,
    active_location_id: Option<String>,
    current_entry_point_id: Option<String>,
    overworld_pawn_cell: Option<GridCoord>,
    return_outdoor_location_id: Option<String>,
    unlocked_locations: UnlockedLocationSet,
    active_overworld_id: Option<String>,
    ai_controllers: HashMap<ActorId, Box<dyn RuntimeAiController>>,
    grid_world: GridWorld,
    pending_progression: VecDeque<PendingProgressionStep>,
    next_actor_id: u64,
    next_registration_index: usize,
    events: Vec<SimulationEvent>,
}

impl Default for Simulation {
    fn default() -> Self {
        let mut simulation = Self {
            config: TurnConfig::default(),
            turn: TurnRuntime::default(),
            group_orders: GroupOrderRegistry::default(),
            active_actions: ActiveActions::default(),
            actors: ActorRegistry::default(),
            actor_interactions: HashMap::new(),
            actor_attack_ranges: HashMap::new(),
            actor_combat_attributes: HashMap::new(),
            actor_resources: HashMap::new(),
            actor_loot_tables: HashMap::new(),
            actor_progression: HashMap::new(),
            actor_xp_rewards: HashMap::new(),
            actor_skill_states: HashMap::new(),
            quest_library: None,
            skill_library: None,
            recipe_library: None,
            shop_library: None,
            dialogue_library: None,
            dialogue_rule_library: None,
            active_quests: BTreeMap::new(),
            completed_quests: BTreeSet::new(),
            actor_relationships: HashMap::new(),
            actor_autonomous_movement_goals: HashMap::new(),
            active_dialogues: HashMap::new(),
            actor_runtime_actions: HashMap::new(),
            economy: HeadlessEconomyRuntime::default(),
            item_library: None,
            map_library: None,
            overworld_library: None,
            interaction_context: InteractionContextSnapshot::default(),
            active_location_id: None,
            current_entry_point_id: None,
            overworld_pawn_cell: None,
            return_outdoor_location_id: None,
            unlocked_locations: BTreeSet::new(),
            active_overworld_id: None,
            ai_controllers: HashMap::new(),
            grid_world: GridWorld::default(),
            pending_progression: VecDeque::new(),
            next_actor_id: 1,
            next_registration_index: 0,
            events: Vec::new(),
        };
        simulation.register_group("player", 0);
        simulation.register_group("friendly", 10);
        simulation
    }
}

impl Simulation {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn grid_world(&self) -> &GridWorld {
        &self.grid_world
    }

    pub fn grid_world_mut(&mut self) -> &mut GridWorld {
        &mut self.grid_world
    }

    pub fn drain_events(&mut self) -> Vec<SimulationEvent> {
        std::mem::take(&mut self.events)
    }

    pub fn push_event(&mut self, event: SimulationEvent) {
        self.events.push(event);
    }

    pub fn economy(&self) -> &HeadlessEconomyRuntime {
        &self.economy
    }

    pub fn economy_mut(&mut self) -> &mut HeadlessEconomyRuntime {
        &mut self.economy
    }

    pub fn set_item_library(&mut self, items: ItemLibrary) {
        self.item_library = Some(items);
    }

    pub fn set_map_library(&mut self, maps: MapLibrary) {
        self.map_library = Some(maps);
    }

    pub(crate) fn ensure_container_for_map_object(
        &mut self,
        object: &MapObjectDefinition,
    ) -> Option<String> {
        let container = object.props.container.as_ref()?;
        let map_id = self.grid_world.map_id()?.as_str().to_string();
        let container_id = format!("{}::{}", map_id, object.object_id);
        let display_name =
            crate::simulation::interaction_behaviors::interactive_object_display_name(object);
        let initial_inventory = container.initial_inventory.iter().filter_map(|entry| {
            entry
                .item_id
                .trim()
                .parse::<u32>()
                .ok()
                .map(|item_id| (item_id, entry.count))
        });
        self.economy.ensure_container(
            container_id.clone(),
            map_id,
            object.object_id.clone(),
            display_name,
            initial_inventory,
        );
        Some(container_id)
    }

    pub(crate) fn ensure_current_map_containers(&mut self) {
        let objects = self.grid_world.map_object_entries();
        for object in &objects {
            let _ = self.ensure_container_for_map_object(object);
        }
    }

    pub fn set_overworld_library(&mut self, overworld: OverworldLibrary) {
        self.active_overworld_id = overworld
            .first()
            .map(|definition| definition.id.as_str().to_string());
        if let Some(definition) = overworld.first() {
            self.unlocked_locations = definition
                .locations
                .iter()
                .filter(|location| location.default_unlocked)
                .map(|location| location.id.as_str().to_string())
                .collect();
        }
        self.overworld_library = Some(overworld);
    }

    pub fn seed_overworld_state(
        &mut self,
        world_mode: WorldMode,
        active_location_id: Option<String>,
        entry_point_id: Option<String>,
        unlocked_locations: impl IntoIterator<Item = String>,
    ) -> Result<(), String> {
        self.unlocked_locations.extend(unlocked_locations);
        let _ =
            self.apply_seeded_overworld_transition(world_mode, active_location_id, entry_point_id)?;
        if world_mode == WorldMode::Overworld {
            self.reset_runtime_actor_occupancy();
            self.load_overworld_topology()?;
            self.sync_interaction_context_from_runtime();
        }
        Ok(())
    }

    pub fn set_quest_library(&mut self, quests: QuestLibrary) {
        self.quest_library = Some(quests);
    }

    pub fn set_skill_library(&mut self, skills: SkillLibrary) {
        self.skill_library = Some(skills);
    }

    pub fn set_recipe_library(&mut self, recipes: RecipeLibrary) {
        let actor_ids: Vec<ActorId> = self.actors.ids().collect();
        for actor_id in actor_ids {
            self.economy.initialize_actor_defaults(actor_id, &recipes);
        }
        self.recipe_library = Some(recipes);
    }

    pub fn set_shop_library(&mut self, shops: ShopLibrary) {
        self.economy.seed_shops_from_library(&shops);
        self.shop_library = Some(shops);
    }

    pub fn set_dialogue_library(&mut self, dialogues: DialogueLibrary) {
        self.dialogue_library = Some(dialogues);
    }

    pub fn set_dialogue_rule_library(&mut self, rules: DialogueRuleLibrary) {
        self.dialogue_rule_library = Some(rules);
    }

    pub fn active_quest_ids_for_actor(&self, actor_id: ActorId) -> BTreeSet<String> {
        self.active_quests
            .values()
            .filter(|state| state.owner_actor_id == actor_id)
            .map(|state| state.quest_id.clone())
            .collect()
    }

    pub fn completed_quest_ids(&self) -> BTreeSet<String> {
        self.completed_quests.clone()
    }

    pub fn get_relationship_score(&self, actor_id: ActorId, target_actor_id: ActorId) -> i32 {
        self.actor_relationships
            .get(&(actor_id, target_actor_id))
            .copied()
            .unwrap_or_else(|| self.default_relationship_score(actor_id, target_actor_id))
    }

    fn default_relationship_score(&self, actor_id: ActorId, target_actor_id: ActorId) -> i32 {
        let actor_side = self.get_actor_side(actor_id).unwrap_or(ActorSide::Neutral);
        let target_side = self
            .get_actor_side(target_actor_id)
            .unwrap_or(ActorSide::Neutral);
        default_relationship_score_for_sides(actor_side, target_side)
    }

    pub fn set_relationship_score(
        &mut self,
        actor_id: ActorId,
        target_actor_id: ActorId,
        score: i32,
    ) -> i32 {
        let score = score.clamp(-100, 100);
        self.actor_relationships
            .insert((actor_id, target_actor_id), score);
        score
    }

    pub fn adjust_relationship_score(
        &mut self,
        actor_id: ActorId,
        target_actor_id: ActorId,
        delta: i32,
    ) -> i32 {
        let next = self
            .get_relationship_score(actor_id, target_actor_id)
            .saturating_add(delta)
            .clamp(-100, 100);
        self.actor_relationships
            .insert((actor_id, target_actor_id), next);
        next
    }

    pub fn set_actor_autonomous_movement_goal(&mut self, actor_id: ActorId, goal: GridCoord) {
        if self.actors.contains(actor_id) {
            self.actor_autonomous_movement_goals.insert(actor_id, goal);
        }
    }

    pub fn clear_actor_autonomous_movement_goal(&mut self, actor_id: ActorId) {
        self.actor_autonomous_movement_goals.remove(&actor_id);
    }

    pub fn autonomous_movement_goal(&self, actor_id: ActorId) -> Option<GridCoord> {
        self.actor_autonomous_movement_goals.get(&actor_id).copied()
    }

    pub fn get_actor_autonomous_movement_goal(&self, actor_id: ActorId) -> Option<GridCoord> {
        self.autonomous_movement_goal(actor_id)
    }

    pub fn set_actor_runtime_action_state(
        &mut self,
        actor_id: ActorId,
        state: NpcRuntimeActionState,
    ) {
        if !self.actors.contains(actor_id) {
            return;
        }
        self.actor_runtime_actions.insert(actor_id, state);
    }

    pub fn get_actor_runtime_action_state(
        &self,
        actor_id: ActorId,
    ) -> Option<&NpcRuntimeActionState> {
        self.actor_runtime_actions.get(&actor_id)
    }

    pub fn clear_actor_runtime_action_state(&mut self, actor_id: ActorId) {
        self.actor_runtime_actions.remove(&actor_id);
    }

    pub fn export_actor_background_state(&self, actor_id: ActorId) -> Option<NpcBackgroundState> {
        let actor = self.actors.get(actor_id)?;
        Some(NpcBackgroundState {
            definition_id: actor
                .definition_id
                .as_ref()
                .map(|definition_id| definition_id.as_str().to_string()),
            display_name: actor.display_name.clone(),
            map_id: self.grid_world.map_id().cloned(),
            grid_position: actor.grid_position,
            current_anchor: self
                .actor_runtime_actions
                .get(&actor_id)
                .and_then(|state| state.current_anchor.clone()),
            current_plan: self
                .actor_runtime_actions
                .get(&actor_id)
                .map(|state| vec![state.step.clone()])
                .unwrap_or_default(),
            plan_next_index: 0,
            current_action: self.actor_runtime_actions.get(&actor_id).cloned(),
            held_reservations: self
                .actor_runtime_actions
                .get(&actor_id)
                .map(|state| state.held_reservations.clone())
                .unwrap_or_default(),
            hunger: 0,
            energy: 0,
            morale: 0,
            on_shift: false,
            meal_window_open: false,
            quiet_hours: false,
            world_alert_active: false,
        })
    }

    pub fn import_actor_background_state(
        &mut self,
        actor_id: ActorId,
        background: &NpcBackgroundState,
    ) {
        if !self.actors.contains(actor_id) {
            return;
        }
        self.update_actor_grid_position(actor_id, background.grid_position);
        if let Some(action) = background.current_action.clone() {
            self.actor_runtime_actions.insert(actor_id, action.clone());
            if let Some(goal) = action.goal_grid {
                self.actor_autonomous_movement_goals.insert(actor_id, goal);
            }
        } else {
            self.actor_runtime_actions.remove(&actor_id);
            self.actor_autonomous_movement_goals.remove(&actor_id);
        }
    }

    pub fn is_quest_active(&self, quest_id: &str) -> bool {
        self.active_quests.contains_key(quest_id)
    }

    pub fn is_quest_completed(&self, quest_id: &str) -> bool {
        self.completed_quests.contains(quest_id)
    }

    pub fn seed_actor_combat_profile(
        &mut self,
        actor_id: ActorId,
        combat_attributes: BTreeMap<String, f32>,
        resources: BTreeMap<String, CharacterResourcePool>,
    ) {
        if !self.actors.contains(actor_id) {
            return;
        }
        self.actor_combat_attributes
            .insert(actor_id, combat_attributes);
        self.actor_resources.insert(
            actor_id,
            resources
                .into_iter()
                .map(|(key, pool)| (key, pool.current.max(0.0)))
                .collect(),
        );
    }

    pub fn set_actor_combat_attribute(
        &mut self,
        actor_id: ActorId,
        attribute: impl Into<String>,
        value: f32,
    ) {
        if !self.actors.contains(actor_id) {
            return;
        }
        self.actor_combat_attributes
            .entry(actor_id)
            .or_default()
            .insert(attribute.into(), value);
    }

    pub fn set_actor_resource(
        &mut self,
        actor_id: ActorId,
        resource: impl Into<String>,
        value: f32,
    ) {
        if !self.actors.contains(actor_id) {
            return;
        }
        self.actor_resources
            .entry(actor_id)
            .or_default()
            .insert(resource.into(), value.max(0.0));
    }

    pub fn seed_actor_loot_table(&mut self, actor_id: ActorId, loot: Vec<CharacterLootEntry>) {
        if !self.actors.contains(actor_id) {
            return;
        }
        self.actor_loot_tables.insert(actor_id, loot);
    }

    pub fn actor_hit_points(&self, actor_id: ActorId) -> f32 {
        self.actor_resource_value(actor_id, "hp")
    }

    pub fn actor_resource(&self, actor_id: ActorId, resource: &str) -> f32 {
        self.actor_resource_value(actor_id, resource)
    }

    pub fn actor_combat_attribute(&self, actor_id: ActorId, attribute: &str) -> f32 {
        self.actor_combat_attribute_value(actor_id, attribute)
    }

    pub fn max_hit_points(&self, actor_id: ActorId) -> f32 {
        self.actor_max_hit_points(actor_id)
    }

    pub fn inventory_count(&self, actor_id: ActorId, item_id: &str) -> i32 {
        item_id
            .trim()
            .parse::<u32>()
            .ok()
            .and_then(|item_id| self.economy.inventory_count(actor_id, item_id))
            .unwrap_or(0)
    }

    pub fn turn_state(&self) -> TurnState {
        TurnState {
            combat_active: self.turn.combat_active,
            current_actor_id: self.turn.current_actor_id,
            current_group_id: self.turn.current_group_id.clone(),
            current_turn_index: self.turn.combat_turn_index,
        }
    }

    pub fn apply_command(&mut self, command: SimulationCommand) -> SimulationCommandResult {
        match command {
            SimulationCommand::RegisterGroup { group_id, order } => {
                self.register_group(group_id, order);
                SimulationCommandResult::None
            }
            SimulationCommand::UnregisterActor { actor_id } => {
                self.unregister_actor(actor_id);
                SimulationCommandResult::None
            }
            SimulationCommand::SetActorAp { actor_id, ap } => {
                self.set_actor_ap(actor_id, ap);
                SimulationCommandResult::None
            }
            SimulationCommand::EnterCombat {
                trigger_actor,
                target_actor,
            } => {
                self.enter_combat(trigger_actor, target_actor);
                SimulationCommandResult::None
            }
            SimulationCommand::ForceEndCombat => {
                self.force_end_combat();
                SimulationCommandResult::None
            }
            SimulationCommand::RequestAction(request) => {
                SimulationCommandResult::Action(self.request_action(request))
            }
            SimulationCommand::RegisterStaticObstacle { grid } => {
                self.grid_world.register_static_obstacle(grid);
                SimulationCommandResult::None
            }
            SimulationCommand::UnregisterStaticObstacle { grid } => {
                self.grid_world.unregister_static_obstacle(grid);
                SimulationCommandResult::None
            }
            SimulationCommand::UpdateActorGridPosition { actor_id, grid } => {
                self.update_actor_grid_position(actor_id, grid);
                SimulationCommandResult::None
            }
            SimulationCommand::MoveActorTo { actor_id, goal } => {
                SimulationCommandResult::Action(self.move_actor_to(actor_id, goal))
            }
            SimulationCommand::PerformAttack {
                actor_id,
                target_actor,
            } => SimulationCommandResult::Action(self.perform_attack(actor_id, target_actor)),
            SimulationCommand::ActivateSkill {
                actor_id,
                skill_id,
                target,
            } => SimulationCommandResult::SkillActivation(
                self.activate_skill(actor_id, &skill_id, target),
            ),
            SimulationCommand::PerformInteract { actor_id } => {
                SimulationCommandResult::Action(self.perform_interact(actor_id))
            }
            SimulationCommand::QueryInteractionOptions {
                actor_id,
                target_id,
            } => {
                let prompt = self.query_interaction_options(actor_id, &target_id);
                if let Some(prompt) = prompt.as_ref() {
                    self.events
                        .push(SimulationEvent::InteractionOptionsResolved {
                            actor_id,
                            target_id: target_id.clone(),
                            option_count: prompt.options.len(),
                        });
                }
                SimulationCommandResult::InteractionPrompt(prompt.unwrap_or_default())
            }
            SimulationCommand::ExecuteInteraction(request) => {
                SimulationCommandResult::InteractionExecution(self.execute_interaction(request))
            }
            SimulationCommand::AdvanceDialogue {
                actor_id,
                target_id,
                dialogue_id,
                option_id,
                option_index,
            } => SimulationCommandResult::DialogueState(self.advance_dialogue(
                actor_id,
                target_id.as_ref(),
                &dialogue_id,
                option_id.as_deref(),
                option_index,
            )),
            SimulationCommand::EndTurn { actor_id } => {
                SimulationCommandResult::Action(self.end_turn(actor_id))
            }
            SimulationCommand::FindPath {
                actor_id,
                start,
                goal,
            } => {
                let result = self.find_path_grid(actor_id, start, goal);
                if let Ok(path) = &result {
                    self.events.push(SimulationEvent::PathComputed {
                        actor_id,
                        path_length: path.len(),
                    });
                }
                SimulationCommandResult::Path(result)
            }
            SimulationCommand::TravelToMap {
                actor_id,
                target_map_id,
                entry_point_id,
                world_mode,
            } => SimulationCommandResult::InteractionContext(self.travel_to_map(
                actor_id,
                &target_map_id,
                entry_point_id.as_deref(),
                world_mode,
            )),
            SimulationCommand::EnterLocation {
                actor_id,
                location_id,
                entry_point_id,
            } => SimulationCommandResult::LocationTransition(self.enter_location(
                actor_id,
                &location_id,
                entry_point_id.as_deref(),
            )),
            SimulationCommand::ReturnToOverworld { actor_id } => {
                SimulationCommandResult::OverworldState(self.return_to_overworld(actor_id))
            }
            SimulationCommand::UnlockLocation { location_id } => {
                SimulationCommandResult::OverworldState(self.unlock_location(&location_id))
            }
        }
    }

    pub fn register_group(&mut self, group_id: impl Into<String>, order: i32) {
        let group_id = group_id.into();
        if group_id.trim().is_empty() {
            return;
        }
        self.group_orders.orders.insert(group_id.clone(), order);
        self.events
            .push(SimulationEvent::GroupRegistered { group_id, order });
    }

    pub fn register_actor(&mut self, params: RegisterActor) -> ActorId {
        let RegisterActor {
            definition_id,
            display_name,
            kind,
            side,
            group_id,
            grid_position,
            interaction,
            attack_range,
            ai_controller,
        } = params;
        let actor_id = ActorId(self.next_actor_id);
        self.next_actor_id += 1;

        let group_id = if group_id.trim().is_empty() {
            "friendly".to_string()
        } else {
            group_id
        };

        if !self.group_orders.orders.contains_key(&group_id) {
            self.register_group(group_id.clone(), 100 + self.next_registration_index as i32);
        }

        self.grid_world
            .set_runtime_actor_grid(actor_id, grid_position);

        self.actors.insert(ActorRecord {
            actor_id,
            definition_id,
            display_name,
            kind,
            side,
            group_id: group_id.clone(),
            registration_index: self.next_registration_index,
            ap: 0.0,
            turn_open: false,
            in_combat: self.turn.combat_active,
            grid_position,
        });
        let existing_actor_ids: Vec<ActorId> = self
            .actors
            .ids()
            .filter(|existing_actor_id| *existing_actor_id != actor_id)
            .collect();
        for existing_actor_id in existing_actor_ids {
            let forward_score = self.default_relationship_score(actor_id, existing_actor_id);
            self.actor_relationships
                .insert((actor_id, existing_actor_id), forward_score);
            let backward_score = self.default_relationship_score(existing_actor_id, actor_id);
            self.actor_relationships
                .insert((existing_actor_id, actor_id), backward_score);
        }
        self.next_registration_index += 1;
        if let Some(interaction) = interaction {
            self.actor_interactions.insert(actor_id, interaction);
        }
        self.actor_attack_ranges
            .insert(actor_id, attack_range.max(0.0));
        self.economy.ensure_actor(actor_id);
        if let Some(recipes) = self.recipe_library.as_ref() {
            self.economy.initialize_actor_defaults(actor_id, recipes);
        }

        if let Some(ai_controller) = ai_controller {
            self.ai_controllers.insert(actor_id, ai_controller);
        }

        self.events.push(SimulationEvent::ActorRegistered {
            actor_id,
            group_id,
            side,
        });

        self.maybe_start_initial_player_turn(actor_id);
        actor_id
    }

    pub fn unregister_actor(&mut self, actor_id: ActorId) {
        if !self.actors.contains(actor_id) {
            return;
        }

        self.active_dialogues.retain(|session_actor_id, session| {
            match session.target_id.as_ref() {
                Some(InteractionTargetId::Actor(target_actor_id)) => {
                    *session_actor_id != actor_id && *target_actor_id != actor_id
                }
                _ => *session_actor_id != actor_id,
            }
        });
        self.actors.remove(actor_id);
        self.actor_interactions.remove(&actor_id);
        self.actor_attack_ranges.remove(&actor_id);
        self.actor_combat_attributes.remove(&actor_id);
        self.actor_resources.remove(&actor_id);
        self.actor_loot_tables.remove(&actor_id);
        self.actor_progression.remove(&actor_id);
        self.actor_xp_rewards.remove(&actor_id);
        self.actor_skill_states.remove(&actor_id);
        self.actor_relationships
            .retain(|(source_actor_id, target_actor_id), _| {
                *source_actor_id != actor_id && *target_actor_id != actor_id
            });
        self.actor_autonomous_movement_goals.remove(&actor_id);
        self.active_dialogues.retain(|owner_actor_id, session| {
            if *owner_actor_id == actor_id {
                return false;
            }
            !matches!(session.target_id, Some(InteractionTargetId::Actor(target_actor_id)) if target_actor_id == actor_id)
        });
        self.actor_runtime_actions.remove(&actor_id);
        self.economy.remove_actor(actor_id);
        self.ai_controllers.remove(&actor_id);
        self.active_actions.by_actor.remove(&actor_id);
        self.grid_world.unregister_runtime_actor(actor_id);
        if self.turn.current_actor_id == Some(actor_id) {
            self.turn.current_actor_id = None;
            self.turn.current_group_id = None;
        }

        self.events
            .push(SimulationEvent::ActorUnregistered { actor_id });
        let _ = self.exit_combat_if_resolved();
    }

    pub fn set_actor_ap(&mut self, actor_id: ActorId, ap: f32) {
        if let Some(actor) = self.actors.get_mut(actor_id) {
            actor.ap = ap.clamp(0.0, self.config.turn_ap_max);
        }
    }

    pub fn get_actor_ap(&self, actor_id: ActorId) -> f32 {
        self.actors
            .get(actor_id)
            .map(|actor| actor.ap)
            .unwrap_or(0.0)
    }

    pub fn get_actor_available_steps(&self, actor_id: ActorId) -> i32 {
        (self.get_actor_ap(actor_id) / self.config.action_cost).floor() as i32
    }

    pub fn can_actor_afford(
        &self,
        actor_id: ActorId,
        action_type: ActionType,
        steps: Option<u32>,
    ) -> bool {
        let payload = ActionRequest {
            actor_id,
            action_type,
            phase: ActionPhase::Start,
            steps,
            target_actor: None,
            cost_override: None,
            success: true,
        };
        self.get_actor_ap(actor_id) >= self.resolve_action_cost(action_type, &payload)
    }

    pub fn attack_action_cost(&self, actor_id: ActorId) -> f32 {
        self.resolve_attack_action_cost(actor_id)
    }

    pub fn get_actor_side(&self, actor_id: ActorId) -> Option<ActorSide> {
        self.actors.get(actor_id).map(|actor| actor.side)
    }

    pub fn are_actors_hostile(&self, actor_id: ActorId, target_actor_id: ActorId) -> bool {
        let Some(actor_side) = self.get_actor_side(actor_id) else {
            return false;
        };
        let Some(target_side) = self.get_actor_side(target_actor_id) else {
            return false;
        };
        matches!(
            (actor_side, target_side),
            (ActorSide::Hostile, ActorSide::Player | ActorSide::Friendly)
                | (ActorSide::Friendly | ActorSide::Player, ActorSide::Hostile)
        )
    }

    pub fn get_actor_group_id(&self, actor_id: ActorId) -> Option<&str> {
        self.actors
            .get(actor_id)
            .map(|actor| actor.group_id.as_str())
    }

    pub fn get_actor_definition_id(&self, actor_id: ActorId) -> Option<&CharacterId> {
        self.actors
            .get(actor_id)
            .and_then(|actor| actor.definition_id.as_ref())
    }

    pub fn actor_grid_position(&self, actor_id: ActorId) -> Option<GridCoord> {
        self.actors.get(actor_id).map(|actor| actor.grid_position)
    }

    pub fn is_actor_current_turn(&self, actor_id: ActorId) -> bool {
        self.turn.combat_active && self.turn.current_actor_id == Some(actor_id)
    }

    pub fn is_actor_input_allowed(&self, actor_id: ActorId) -> bool {
        !self.turn.combat_active || self.turn.current_actor_id == Some(actor_id)
    }

    pub fn current_actor(&self) -> Option<ActorId> {
        self.turn.current_actor_id
    }

    pub fn current_group(&self) -> Option<&str> {
        self.turn.current_group_id.as_deref()
    }

    pub fn current_turn_index(&self) -> u64 {
        self.turn.combat_turn_index
    }

    pub fn has_pending_progression(&self) -> bool {
        !self.pending_progression.is_empty()
    }

    pub fn peek_pending_progression(&self) -> Option<&PendingProgressionStep> {
        self.pending_progression.front()
    }

    pub fn clear_pending_progression(&mut self) {
        self.pending_progression.clear();
    }

    pub fn queue_pending_progression(&mut self, step: PendingProgressionStep) {
        self.pending_progression.push_back(step);
    }

    pub(crate) fn pop_pending_progression(&mut self) -> Option<PendingProgressionStep> {
        self.pending_progression.pop_front()
    }

    pub(crate) fn apply_pending_progression_step(&mut self, step: PendingProgressionStep) {
        match step {
            PendingProgressionStep::EndCurrentCombatTurn => {
                self.end_current_combat_turn();
                if self.turn.combat_active {
                    if let Some(actor_id) = self.turn.current_actor_id {
                        if self.get_actor_side(actor_id) != Some(ActorSide::Player) {
                            self.run_combat_ai_turn(actor_id);
                        }
                    }
                }
            }
            PendingProgressionStep::RunNonCombatWorldCycle => self.run_world_cycle(),
            PendingProgressionStep::StartNextNonCombatPlayerTurn => {
                self.start_next_noncombat_player_turn()
            }
            PendingProgressionStep::ContinuePendingMovement => {}
        }
    }

    pub fn is_in_combat(&self) -> bool {
        self.turn.combat_active
    }

    pub fn actor_in_combat(&self, actor_id: ActorId) -> bool {
        self.actors
            .get(actor_id)
            .map(|actor| actor.in_combat)
            .unwrap_or(false)
    }

    pub fn query_combat_ai(&self, actor_id: ActorId) -> Option<CombatAiSnapshot> {
        self.build_combat_ai_snapshot(actor_id)
    }

    pub fn run_combat_ai_intent(
        &mut self,
        actor_id: ActorId,
        intent: CombatAiIntent,
    ) -> CombatAiExecutionResult {
        self.execute_combat_ai_intent(actor_id, intent)
    }

    pub fn grid_walkable(&self, grid: GridCoord) -> bool {
        self.grid_world.is_walkable(grid)
    }

    pub fn grid_walkable_for_actor(&self, grid: GridCoord, actor_id: Option<ActorId>) -> bool {
        self.grid_world.is_walkable_for_actor(grid, actor_id)
    }

    pub fn drop_item_to_ground(
        &mut self,
        actor_id: ActorId,
        item_id: u32,
        count: i32,
    ) -> Result<DropItemOutcome, String> {
        if count <= 0 {
            return Err("invalid_drop_count".to_string());
        }

        let actor_grid = self
            .actor_grid_position(actor_id)
            .ok_or_else(|| format!("unknown_actor:{}", actor_id.0))?;
        let inventory_count = self.economy.inventory_count(actor_id, item_id).unwrap_or(0);
        if inventory_count < count {
            return Err(format!("insufficient_item_count:{item_id}"));
        }

        self.economy
            .remove_item(actor_id, item_id, count)
            .map_err(|error| error.to_string())?;

        let drop_grid = self.find_ground_drop_grid(actor_grid);
        Ok(self.spawn_drop_pickup(actor_id, item_id, count, drop_grid))
    }

    pub fn drop_equipped_item_to_ground(
        &mut self,
        actor_id: ActorId,
        slot: &str,
    ) -> Result<DropItemOutcome, String> {
        let actor_grid = self
            .actor_grid_position(actor_id)
            .ok_or_else(|| format!("unknown_actor:{}", actor_id.0))?;
        let item_id = self
            .economy
            .equipped_item(actor_id, slot)
            .map(|equipped| equipped.item_id)
            .ok_or_else(|| format!("empty_equipment_slot:{}", slot.trim()))?;

        self.economy
            .unequip_item(actor_id, slot)
            .map_err(|error| error.to_string())?;
        self.economy
            .remove_item(actor_id, item_id, 1)
            .map_err(|error| error.to_string())?;

        let drop_grid = self.find_ground_drop_grid(actor_grid);
        Ok(self.spawn_drop_pickup(actor_id, item_id, 1, drop_grid))
    }

    pub fn grid_runtime_blocked_cells(&self) -> Vec<GridCoord> {
        self.grid_world.runtime_blocked_cells()
    }

    pub fn update_actor_grid_position(&mut self, actor_id: ActorId, grid: GridCoord) {
        if let Some(actor) = self.actors.get_mut(actor_id) {
            actor.grid_position = grid;
            self.grid_world.set_runtime_actor_grid(actor_id, grid);
        }
    }

    fn apply_actor_movement_path(&mut self, actor_id: ActorId, path: &[GridCoord]) {
        let Some(mut previous) = path.first().copied() else {
            return;
        };
        let total_steps = path.len().saturating_sub(1);

        // Keep movement state observable per cell so later step hooks can interrupt cleanly.
        for (step_index, next) in path.iter().copied().skip(1).enumerate() {
            if let Some(door) = self.grid_world.auto_open_generated_door_at(next) {
                info!(
                    "core.movement.auto_open_generated_door actor={:?} door_id={} grid=({}, {}, {})",
                    actor_id,
                    door.door_id,
                    next.x,
                    next.y,
                    next.z
                );
            }
            self.update_actor_grid_position(actor_id, next);
            self.events.push(SimulationEvent::ActorMoved {
                actor_id,
                from: previous,
                to: next,
                step_index: step_index + 1,
                total_steps,
            });
            previous = next;
        }
    }

    pub fn find_path_grid(
        &self,
        actor_id: Option<ActorId>,
        start: GridCoord,
        goal: GridCoord,
    ) -> Result<Vec<GridCoord>, GridPathfindingError> {
        find_path_grid(&self.grid_world, actor_id, start, goal)
    }

    pub fn find_path_world(
        &self,
        actor_id: Option<ActorId>,
        start: WorldCoord,
        goal: WorldCoord,
    ) -> Result<Vec<WorldCoord>, GridPathfindingError> {
        find_path_world(&self.grid_world, actor_id, start, goal)
    }

    pub fn plan_actor_movement(
        &self,
        actor_id: ActorId,
        goal: GridCoord,
    ) -> Result<MovementPlan, MovementPlanError> {
        let Some(start) = self.actor_grid_position(actor_id) else {
            return Err(MovementPlanError::UnknownActor { actor_id });
        };

        let (requested_goal, requested_path) =
            if self.interaction_context.world_mode == WorldMode::Overworld {
                let definition = self
                    .current_overworld_definition()
                    .map_err(|_| MovementPlanError::NoPath)?;
                let resolved_goal = resolve_overworld_goal(definition, start, goal)
                    .ok_or(MovementPlanError::NoPath)?;
                let path = compute_cell_path(definition, start, resolved_goal)
                    .ok_or(MovementPlanError::NoPath)?;
                (resolved_goal, path)
            } else {
                (
                    goal,
                    self.find_path_grid(Some(actor_id), start, goal)
                        .map_err(MovementPlanError::from)?,
                )
            };
        let available_steps = self.get_actor_available_steps(actor_id).max(0) as usize;
        let resolved_step_count = requested_path.len().saturating_sub(1).min(available_steps);
        let resolved_path = requested_path
            .iter()
            .copied()
            .take(resolved_step_count + 1)
            .collect::<Vec<_>>();
        let resolved_goal = resolved_path.last().copied().unwrap_or(start);

        Ok(MovementPlan {
            actor_id,
            start,
            requested_goal,
            requested_path,
            resolved_goal,
            resolved_path,
            available_steps,
        })
    }

    pub fn move_actor_to_reachable(
        &mut self,
        actor_id: ActorId,
        goal: GridCoord,
    ) -> Result<MovementCommandOutcome, MovementPlanError> {
        let plan = self.plan_actor_movement(actor_id, goal)?;
        let result = if plan.requested_steps() == 0 {
            let ap = self.get_actor_ap(actor_id);
            ActionResult::accepted(ap, ap, 0.0, self.turn.combat_active)
        } else if plan.resolved_steps() == 0 {
            let ap = self.get_actor_ap(actor_id);
            ActionResult::rejected("insufficient_ap", ap, ap, self.turn.combat_active)
        } else if self.interaction_context.world_mode == WorldMode::Overworld {
            self.move_actor_along_path(actor_id, &plan.resolved_path)
        } else {
            self.move_actor_to(actor_id, plan.resolved_goal)
        };

        Ok(MovementCommandOutcome { plan, result })
    }

    pub(crate) fn current_overworld_definition(&self) -> Result<&OverworldDefinition, String> {
        let Some(library) = self.overworld_library.as_ref() else {
            return Err("overworld_library_missing".to_string());
        };
        if let Some(active_overworld_id) = self.active_overworld_id.as_deref() {
            if let Some((_, definition)) = library
                .iter()
                .find(|(id, _)| id.as_str() == active_overworld_id)
            {
                return Ok(definition);
            }
        }
        library
            .first()
            .ok_or_else(|| "overworld_definition_missing".to_string())
    }

    fn actor_combat_attribute_value(&self, actor_id: ActorId, attribute: &str) -> f32 {
        self.actor_combat_attributes
            .get(&actor_id)
            .and_then(|attributes| attributes.get(attribute))
            .copied()
            .unwrap_or(0.0)
    }

    fn actor_equipment_attribute_bonus(&self, actor_id: ActorId, attribute: &str) -> f32 {
        let Some(items) = self.item_library.as_ref() else {
            return 0.0;
        };
        self.economy
            .equipment_attribute_totals(actor_id, items)
            .ok()
            .and_then(|totals| totals.get(attribute).copied())
            .unwrap_or(0.0)
    }

    fn actor_resource_value(&self, actor_id: ActorId, resource: &str) -> f32 {
        self.actor_resources
            .get(&actor_id)
            .and_then(|resources| resources.get(resource))
            .copied()
            .unwrap_or_else(|| {
                if resource == "hp" {
                    self.actor_max_hit_points(actor_id)
                } else {
                    0.0
                }
            })
    }

    fn actor_max_hit_points(&self, actor_id: ActorId) -> f32 {
        (self.actor_combat_attribute_value(actor_id, "max_hp")
            + self.actor_equipment_attribute_bonus(actor_id, "max_hp"))
        .max(1.0)
    }
}

fn default_relationship_score_for_sides(actor_side: ActorSide, target_side: ActorSide) -> i32 {
    match (actor_side, target_side) {
        (ActorSide::Player, ActorSide::Player) => 60,
        (ActorSide::Hostile, _) | (_, ActorSide::Hostile) => -60,
        (ActorSide::Neutral, _) | (_, ActorSide::Neutral) => 0,
        (ActorSide::Friendly, _) | (_, ActorSide::Friendly) => 40,
    }
}

pub(super) fn dialogue_advance_error_reason(error: game_data::DialogueAdvanceError) -> String {
    match error {
        game_data::DialogueAdvanceError::MissingNode { node_id } => {
            format!("dialogue_node_missing:{node_id}")
        }
        game_data::DialogueAdvanceError::ChoiceRequired { node_id } => {
            format!("dialogue_choice_required:{node_id}")
        }
        game_data::DialogueAdvanceError::InvalidChoice {
            node_id,
            choice_index,
        } => format!("dialogue_choice_invalid:{node_id}:{choice_index}"),
    }
}

pub(super) fn npc_action_key_name(action: NpcActionKey) -> String {
    action.as_str().to_string()
}

pub(super) fn dialogue_action_string(action: &DialogueAction, keys: &[&str]) -> Option<String> {
    keys.iter().find_map(|key| {
        action
            .extra
            .get(*key)
            .and_then(|value| value.as_str())
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .map(str::to_string)
    })
}

pub(super) fn dialogue_action_i32(action: &DialogueAction, keys: &[&str]) -> Option<i32> {
    keys.iter().find_map(|key| {
        let value = action.extra.get(*key)?;
        value
            .as_i64()
            .and_then(|number| i32::try_from(number).ok())
            .or_else(|| value.as_u64().and_then(|number| i32::try_from(number).ok()))
            .or_else(|| {
                value.as_str().and_then(|text| {
                    text.trim()
                        .parse::<i64>()
                        .ok()
                        .and_then(|number| i32::try_from(number).ok())
                })
            })
    })
}

pub(super) fn dialogue_action_u32(action: &DialogueAction, keys: &[&str]) -> Option<u32> {
    keys.iter().find_map(|key| {
        let value = action.extra.get(*key)?;
        value
            .as_u64()
            .and_then(|number| u32::try_from(number).ok())
            .or_else(|| value.as_i64().and_then(|number| u32::try_from(number).ok()))
            .or_else(|| {
                value.as_str().and_then(|text| {
                    text.trim()
                        .parse::<u64>()
                        .ok()
                        .and_then(|number| u32::try_from(number).ok())
                })
            })
    })
}

#[cfg(test)]
mod tests;
