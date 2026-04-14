use std::collections::BTreeSet;

use game_data::{
    ActionType, ActorId, ActorSide, CharacterId, GridCoord, SkillTargetRequest, WorldCoord,
};

use crate::simulation::{
    AttackTargetingQueryResult, CombatAiExecutionResult, CombatAiIntent, CombatAiSnapshot,
    SkillRuntimeState, SkillSpatialPreviewResult, SkillTargetingQueryResult,
};

use super::SimulationRuntime;
use crate::{NpcBackgroundState, NpcRuntimeActionState};

impl SimulationRuntime {
    pub fn world_to_grid(&self, world: WorldCoord) -> GridCoord {
        self.simulation.grid_world().world_to_grid(world)
    }

    pub fn grid_to_world(&self, grid: GridCoord) -> WorldCoord {
        self.simulation.grid_world().grid_to_world(grid)
    }

    pub fn get_actor_grid_position(&self, actor_id: ActorId) -> Option<GridCoord> {
        self.simulation.actor_grid_position(actor_id)
    }

    pub fn get_actor_attack_range(&self, actor_id: ActorId) -> f32 {
        self.simulation.attack_range(actor_id)
    }

    pub fn query_attack_targeting(&self, actor_id: ActorId) -> AttackTargetingQueryResult {
        self.simulation.query_attack_targeting(actor_id)
    }

    pub fn query_skill_targeting(
        &self,
        actor_id: ActorId,
        skill_id: &str,
    ) -> SkillTargetingQueryResult {
        self.simulation.query_skill_targeting(actor_id, skill_id)
    }

    pub fn preview_skill_target(
        &self,
        actor_id: ActorId,
        skill_id: &str,
        target: SkillTargetRequest,
    ) -> SkillSpatialPreviewResult {
        self.simulation
            .preview_skill_target(actor_id, skill_id, target)
    }

    pub fn grid_walkable(&self, grid: GridCoord) -> bool {
        self.simulation.grid_walkable(grid)
    }

    pub fn grid_walkable_for_actor(&self, grid: GridCoord, actor_id: Option<ActorId>) -> bool {
        self.simulation.grid_walkable_for_actor(grid, actor_id)
    }

    pub fn is_grid_in_bounds(&self, grid: GridCoord) -> bool {
        self.simulation.grid_world().is_in_bounds(grid)
    }

    pub fn get_actor_ap(&self, actor_id: ActorId) -> f32 {
        self.simulation.get_actor_ap(actor_id)
    }

    pub fn get_actor_available_steps(&self, actor_id: ActorId) -> i32 {
        self.simulation.get_actor_available_steps(actor_id)
    }

    pub fn get_actor_inventory_count(&self, actor_id: ActorId, item_id: &str) -> i32 {
        self.simulation.inventory_count(actor_id, item_id)
    }

    pub fn get_actor_hit_points(&self, actor_id: ActorId) -> f32 {
        self.simulation.actor_hit_points(actor_id)
    }

    pub fn get_actor_level(&self, actor_id: ActorId) -> i32 {
        self.simulation.actor_level(actor_id)
    }

    pub fn get_actor_current_xp(&self, actor_id: ActorId) -> i32 {
        self.simulation.actor_current_xp(actor_id)
    }

    pub fn can_actor_afford(
        &self,
        actor_id: ActorId,
        action_type: ActionType,
        steps: Option<u32>,
    ) -> bool {
        self.simulation
            .can_actor_afford(actor_id, action_type, steps)
    }

    pub fn get_actor_side(&self, actor_id: ActorId) -> Option<ActorSide> {
        self.simulation.get_actor_side(actor_id)
    }

    pub fn get_actor_group_id(&self, actor_id: ActorId) -> Option<&str> {
        self.simulation.get_actor_group_id(actor_id)
    }

    pub fn get_actor_definition_id(&self, actor_id: ActorId) -> Option<&CharacterId> {
        self.simulation.get_actor_definition_id(actor_id)
    }

    pub fn get_actor_combat_behavior_profile(&self, actor_id: ActorId) -> Option<&str> {
        self.simulation.actor_combat_behavior(actor_id)
    }

    pub fn set_actor_autonomous_movement_goal(&mut self, actor_id: ActorId, goal: GridCoord) {
        self.simulation
            .set_actor_autonomous_movement_goal(actor_id, goal);
    }

    pub fn clear_actor_autonomous_movement_goal(&mut self, actor_id: ActorId) {
        self.simulation
            .clear_actor_autonomous_movement_goal(actor_id);
    }

    pub fn get_actor_autonomous_movement_goal(&self, actor_id: ActorId) -> Option<GridCoord> {
        self.simulation.get_actor_autonomous_movement_goal(actor_id)
    }

    pub fn set_actor_runtime_action_state(
        &mut self,
        actor_id: ActorId,
        state: NpcRuntimeActionState,
    ) {
        self.simulation
            .set_actor_runtime_action_state(actor_id, state);
    }

    pub fn get_actor_runtime_action_state(
        &self,
        actor_id: ActorId,
    ) -> Option<&NpcRuntimeActionState> {
        self.simulation.get_actor_runtime_action_state(actor_id)
    }

    pub fn clear_actor_runtime_action_state(&mut self, actor_id: ActorId) {
        self.simulation.clear_actor_runtime_action_state(actor_id);
    }

    pub fn export_actor_background_state(&self, actor_id: ActorId) -> Option<NpcBackgroundState> {
        self.simulation.export_actor_background_state(actor_id)
    }

    pub fn import_actor_background_state(
        &mut self,
        actor_id: ActorId,
        background: &NpcBackgroundState,
    ) {
        self.simulation
            .import_actor_background_state(actor_id, background);
    }

    pub fn active_quest_ids_for_actor(&self, actor_id: ActorId) -> BTreeSet<String> {
        self.simulation.active_quest_ids_for_actor(actor_id)
    }

    pub fn completed_quest_ids(&self) -> BTreeSet<String> {
        self.simulation.completed_quest_ids()
    }

    pub fn get_relationship_score(&self, actor_id: ActorId, target_actor_id: ActorId) -> i32 {
        self.simulation
            .get_relationship_score(actor_id, target_actor_id)
    }

    pub fn set_relationship_score(
        &mut self,
        actor_id: ActorId,
        target_actor_id: ActorId,
        score: i32,
    ) -> i32 {
        self.simulation
            .set_relationship_score(actor_id, target_actor_id, score)
    }

    pub fn adjust_relationship_score(
        &mut self,
        actor_id: ActorId,
        target_actor_id: ActorId,
        delta: i32,
    ) -> i32 {
        self.simulation
            .adjust_relationship_score(actor_id, target_actor_id, delta)
    }

    pub fn actor_turn_open(&self, actor_id: ActorId) -> bool {
        self.simulation.actor_turn_open(actor_id)
    }

    pub fn is_actor_current_turn(&self, actor_id: ActorId) -> bool {
        self.simulation.is_actor_current_turn(actor_id)
    }

    pub fn is_actor_input_allowed(&self, actor_id: ActorId) -> bool {
        self.simulation.is_actor_input_allowed(actor_id)
    }

    pub fn is_in_combat(&self) -> bool {
        self.simulation.is_in_combat()
    }

    pub fn actor_in_combat(&self, actor_id: ActorId) -> bool {
        self.simulation.actor_in_combat(actor_id)
    }

    pub fn current_actor(&self) -> Option<ActorId> {
        self.simulation.current_actor()
    }

    pub fn current_group(&self) -> Option<&str> {
        self.simulation.current_group()
    }

    pub fn skill_state(&self, actor_id: ActorId, skill_id: &str) -> SkillRuntimeState {
        self.simulation.skill_state(actor_id, skill_id)
    }

    pub fn skill_cooldown_remaining(&self, actor_id: ActorId, skill_id: &str) -> f32 {
        self.simulation.skill_cooldown_remaining(actor_id, skill_id)
    }

    pub fn is_skill_toggled_active(&self, actor_id: ActorId, skill_id: &str) -> bool {
        self.simulation.is_skill_toggled_active(actor_id, skill_id)
    }

    pub fn advance_skill_timers(&mut self, delta_sec: f32) {
        self.simulation.advance_skill_timers(delta_sec);
    }

    pub fn current_turn_index(&self) -> u64 {
        self.simulation.current_turn_index()
    }

    pub fn query_combat_ai(&self, actor_id: ActorId) -> Option<CombatAiSnapshot> {
        self.simulation.query_combat_ai(actor_id)
    }

    pub fn execute_combat_ai_intent(
        &mut self,
        actor_id: ActorId,
        intent: CombatAiIntent,
    ) -> CombatAiExecutionResult {
        self.simulation.run_combat_ai_intent(actor_id, intent)
    }
}
