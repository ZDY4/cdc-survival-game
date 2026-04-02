use super::*;

impl SimulationRuntime {
    pub fn new() -> Self {
        Self {
            simulation: Simulation::new(),
            vision: VisionRuntimeState::default(),
            pending_movement: None,
            pending_interaction: None,
            pending_movement_stop_requested: false,
            path_preview: Vec::new(),
            tick_count: 0,
        }
    }

    pub fn from_simulation(simulation: Simulation) -> Self {
        Self {
            simulation,
            vision: VisionRuntimeState::default(),
            pending_movement: None,
            pending_interaction: None,
            pending_movement_stop_requested: false,
            path_preview: Vec::new(),
            tick_count: 0,
        }
    }

    pub fn set_item_library(&mut self, items: ItemLibrary) {
        self.simulation.set_item_library(items);
    }

    pub fn set_map_library(&mut self, maps: MapLibrary) {
        self.simulation.set_map_library(maps);
    }

    pub fn set_overworld_library(&mut self, overworld: OverworldLibrary) {
        self.simulation.set_overworld_library(overworld);
    }

    pub fn seed_overworld_state(
        &mut self,
        world_mode: WorldMode,
        active_location_id: Option<String>,
        entry_point_id: Option<String>,
        unlocked_locations: impl IntoIterator<Item = String>,
    ) -> Result<(), String> {
        self.simulation.seed_overworld_state(
            world_mode,
            active_location_id,
            entry_point_id,
            unlocked_locations,
        )
    }

    pub fn register_actor(&mut self, params: RegisterActor) -> ActorId {
        self.simulation.register_actor(params)
    }

    pub fn unregister_actor(&mut self, actor_id: ActorId) {
        self.clear_pending_movement_internal(None);
        self.vision.clear_actor(actor_id);
        self.simulation.unregister_actor(actor_id);
    }

    pub fn seed_actor_progression(&mut self, actor_id: ActorId, level: i32, xp_reward: i32) {
        self.simulation
            .seed_actor_progression(actor_id, level, xp_reward);
    }

    pub fn seed_actor_combat_profile(
        &mut self,
        actor_id: ActorId,
        combat_attributes: std::collections::BTreeMap<String, f32>,
        resources: std::collections::BTreeMap<String, game_data::CharacterResourcePool>,
    ) {
        self.simulation
            .seed_actor_combat_profile(actor_id, combat_attributes, resources);
    }

    pub fn seed_actor_loot_table(
        &mut self,
        actor_id: ActorId,
        loot: Vec<game_data::CharacterLootEntry>,
    ) {
        self.simulation.seed_actor_loot_table(actor_id, loot);
    }

    pub fn set_quest_library(&mut self, quests: QuestLibrary) {
        self.simulation.set_quest_library(quests);
    }

    pub fn set_skill_library(&mut self, skills: SkillLibrary) {
        self.simulation.set_skill_library(skills);
    }

    pub fn set_recipe_library(&mut self, recipes: RecipeLibrary) {
        self.simulation.set_recipe_library(recipes);
    }

    pub fn set_shop_library(&mut self, shops: ShopLibrary) {
        self.simulation.set_shop_library(shops);
    }

    pub fn set_dialogue_library(&mut self, dialogues: DialogueLibrary) {
        self.simulation.set_dialogue_library(dialogues);
    }

    pub fn set_dialogue_rule_library(&mut self, rules: DialogueRuleLibrary) {
        self.simulation.set_dialogue_rule_library(rules);
    }

    pub fn is_quest_active(&self, quest_id: &str) -> bool {
        self.simulation.is_quest_active(quest_id)
    }

    pub fn is_quest_completed(&self, quest_id: &str) -> bool {
        self.simulation.is_quest_completed(quest_id)
    }

    pub fn tick(&mut self) {
        self.tick_count = self.tick_count.saturating_add(1);
    }

    pub fn tick_count(&self) -> u64 {
        self.tick_count
    }

    pub fn submit_command(&mut self, command: SimulationCommand) -> SimulationCommandResult {
        self.cancel_pending_for_command(&command);
        self.capture_path_preview(&command);
        self.simulation.apply_command(command)
    }

    pub fn drain_events(&mut self) -> Vec<SimulationEvent> {
        self.simulation.drain_events()
    }

    pub fn push_event(&mut self, event: SimulationEvent) {
        self.simulation.push_event(event);
    }
}
