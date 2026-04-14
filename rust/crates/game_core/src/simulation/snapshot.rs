use std::collections::BTreeMap;

use game_data::{GridCoord, MapCellDefinition, MapObjectDefinition, MapObjectKind};

use super::state_persistence::{
    ActorAttackRangeSnapshotEntry, ActorAutonomousMovementGoalSnapshotEntry,
    ActorCombatAttributesSnapshotEntry, ActorCombatBehaviorSnapshotEntry,
    ActorCombatOriginSnapshotEntry, ActorInteractionSnapshotEntry, ActorLootTableSnapshotEntry,
    ActorProgressionSnapshotEntry, ActorRelationshipSnapshotEntry, ActorResourcesSnapshotEntry,
    ActorSkillStateSnapshotEntry, ActorXpRewardSnapshotEntry, DialogueSessionSnapshotEntry,
    SimulationStateSnapshot, SkillRuntimeSnapshotEntry,
};
use super::{
    interaction_behaviors, ActorDebugState, CombatDebugState, GridDebugState, MapCellDebugState,
    MapObjectDebugState, Simulation, SimulationSnapshot,
};
use crate::vision::VisionRuntimeSnapshot;

impl Simulation {
    pub fn actor_debug_states(&self) -> Vec<ActorDebugState> {
        let mut actors: Vec<ActorDebugState> = self
            .actors
            .values()
            .map(|actor| ActorDebugState {
                actor_id: actor.actor_id,
                definition_id: actor.definition_id.clone(),
                display_name: actor.display_name.clone(),
                kind: actor.kind,
                side: actor.side,
                group_id: actor.group_id.clone(),
                ap: actor.ap,
                available_steps: self.get_actor_available_steps(actor.actor_id),
                turn_open: actor.turn_open,
                in_combat: actor.in_combat,
                grid_position: actor.grid_position,
                level: self.actor_level(actor.actor_id),
                current_xp: self.actor_current_xp(actor.actor_id),
                available_stat_points: self
                    .actor_progression
                    .get(&actor.actor_id)
                    .map(|state| state.available_stat_points)
                    .unwrap_or(0),
                available_skill_points: self
                    .actor_progression
                    .get(&actor.actor_id)
                    .map(|state| state.available_skill_points)
                    .unwrap_or(0),
                hp: self.actor_hit_points(actor.actor_id),
                max_hp: self.actor_max_hit_points(actor.actor_id),
            })
            .collect();
        actors.sort_by_key(|actor| actor.actor_id);
        actors
    }

    pub fn map_cell_debug_states(&self) -> Vec<MapCellDebugState> {
        self.grid_world
            .map_cell_entries()
            .into_iter()
            .map(
                |(grid, cell): (GridCoord, MapCellDefinition)| MapCellDebugState {
                    grid,
                    blocks_movement: cell.blocks_movement,
                    blocks_sight: cell.blocks_sight,
                    terrain: cell.terrain,
                    visual: cell.visual,
                },
            )
            .collect()
    }

    pub fn map_object_debug_states(&self) -> Vec<MapObjectDebugState> {
        self.grid_world
            .map_object_entries()
            .into_iter()
            .map(|object: MapObjectDefinition| {
                let mut payload_summary = BTreeMap::new();
                if let Some(visual) = object.props.visual.as_ref() {
                    payload_summary.insert(
                        "prototype_id".to_string(),
                        visual.prototype_id.as_str().to_string(),
                    );
                    payload_summary.insert(
                        "visual_offset_world".to_string(),
                        format!(
                            "{},{},{}",
                            visual.local_offset_world.x,
                            visual.local_offset_world.y,
                            visual.local_offset_world.z
                        ),
                    );
                    payload_summary.insert(
                        "visual_scale".to_string(),
                        format!("{},{},{}", visual.scale.x, visual.scale.y, visual.scale.z),
                    );
                }
                match object.kind {
                    MapObjectKind::Building => {
                        if let Some(building) = object.props.building.as_ref() {
                            payload_summary
                                .insert("prefab_id".to_string(), building.prefab_id.clone());
                        }
                    }
                    MapObjectKind::Prop => {}
                    MapObjectKind::Pickup => {
                        if let Some(pickup) = object.props.pickup.as_ref() {
                            payload_summary.insert("item_id".to_string(), pickup.item_id.clone());
                            payload_summary.insert(
                                "count_range".to_string(),
                                format!("{}..{}", pickup.min_count, pickup.max_count),
                            );
                        }
                    }
                    MapObjectKind::Interactive => {
                        if let Some(interactive) = object.props.interactive.as_ref() {
                            payload_summary.insert(
                                "interaction_kind".to_string(),
                                interactive.interaction_kind.clone(),
                            );
                            if let Some(target_id) = interactive.target_id.as_ref() {
                                payload_summary.insert("target_id".to_string(), target_id.clone());
                            }
                            if interactive
                                .extra
                                .get("generated_door")
                                .and_then(|value| value.as_bool())
                                .unwrap_or(false)
                            {
                                payload_summary
                                    .insert("generated_door".to_string(), "true".to_string());
                                if let Some(door_state) = interactive
                                    .extra
                                    .get("door_state")
                                    .and_then(|value| value.as_str())
                                {
                                    payload_summary
                                        .insert("door_state".to_string(), door_state.to_string());
                                }
                                if let Some(door_locked) = interactive
                                    .extra
                                    .get("door_locked")
                                    .and_then(|value| value.as_bool())
                                {
                                    payload_summary.insert(
                                        "door_locked".to_string(),
                                        door_locked.to_string(),
                                    );
                                }
                            }
                        }
                        if let Some(container) = object.props.container.as_ref() {
                            if let Some(visual_id) = container
                                .visual_id
                                .as_deref()
                                .map(str::trim)
                                .filter(|visual_id| !visual_id.is_empty())
                            {
                                payload_summary.insert(
                                    "container_visual_id".to_string(),
                                    visual_id.to_string(),
                                );
                            }
                        }
                    }
                    MapObjectKind::Trigger => {
                        if let Some(trigger) = object.props.trigger.as_ref() {
                            let options = trigger.resolved_options();
                            if let Some(primary) = options.first() {
                                payload_summary.insert(
                                    "trigger_kind".to_string(),
                                    primary.id.as_str().to_string(),
                                );
                                let target_id =
                                    interaction_behaviors::scene_transition::resolve_scene_target_id(
                                        primary,
                                    );
                                if !target_id.trim().is_empty() {
                                    payload_summary.insert("target_id".to_string(), target_id);
                                }
                            }
                            payload_summary.insert(
                                "trigger_cells".to_string(),
                                self.grid_world
                                    .map_object_footprint_cells(&object.object_id)
                                    .len()
                                    .to_string(),
                            );
                        }
                    }
                    MapObjectKind::AiSpawn => {
                        if let Some(ai_spawn) = object.props.ai_spawn.as_ref() {
                            payload_summary
                                .insert("spawn_id".to_string(), ai_spawn.spawn_id.clone());
                            payload_summary.insert(
                                "character_id".to_string(),
                                ai_spawn.character_id.clone(),
                            );
                        }
                    }
                }

                let occupied_cells = self.grid_world.map_object_footprint_cells(&object.object_id);
                let blocks_movement = game_data::object_effectively_blocks_movement(&object);
                let blocks_sight = game_data::object_effectively_blocks_sight(&object);
                MapObjectDebugState {
                    object_id: object.object_id,
                    kind: object.kind,
                    anchor: object.anchor,
                    footprint: object.footprint,
                    rotation: object.rotation,
                    blocks_movement,
                    blocks_sight,
                    occupied_cells,
                    payload_summary,
                }
            })
            .collect()
    }

    pub fn snapshot(
        &self,
        path_preview: Vec<GridCoord>,
        vision: VisionRuntimeSnapshot,
    ) -> SimulationSnapshot {
        let map_size = self.grid_world.map_size();
        SimulationSnapshot {
            turn: self.turn_state(),
            actors: self.actor_debug_states(),
            grid: GridDebugState {
                grid_size: self.grid_world.grid_size(),
                map_id: self.grid_world.map_id().cloned(),
                map_width: map_size.map(|size| size.width),
                map_height: map_size.map(|size| size.height),
                default_level: self.grid_world.default_level(),
                levels: self.grid_world.levels(),
                static_obstacles: self.grid_world.static_obstacle_cells(),
                map_blocked_cells: self.grid_world.map_blocked_cells(None),
                map_cells: self.map_cell_debug_states(),
                map_objects: self.map_object_debug_states(),
                runtime_blocked_cells: self.grid_world.runtime_blocked_cells(),
                topology_version: self.grid_world.topology_version(),
                runtime_obstacle_version: self.grid_world.runtime_obstacle_version(),
            },
            vision,
            generated_buildings: self.grid_world.generated_buildings().to_vec(),
            generated_doors: self.grid_world.generated_doors().to_vec(),
            combat: CombatDebugState {
                in_combat: self.turn.combat_active,
                current_actor_id: self.turn.current_actor_id,
                current_group_id: self.turn.current_group_id.clone(),
                current_turn_index: self.turn.combat_turn_index,
            },
            interaction_context: self.current_interaction_context(),
            overworld: self.current_overworld_snapshot(),
            path_preview,
        }
    }

    pub(crate) fn save_snapshot(&self) -> SimulationStateSnapshot {
        let mut actor_interactions = self
            .actor_interactions
            .iter()
            .map(|(actor_id, interaction)| ActorInteractionSnapshotEntry {
                actor_id: *actor_id,
                interaction: interaction.clone(),
            })
            .collect::<Vec<_>>();
        actor_interactions.sort_by_key(|entry| entry.actor_id);

        let mut actor_attack_ranges = self
            .actor_attack_ranges
            .iter()
            .map(|(actor_id, attack_range)| ActorAttackRangeSnapshotEntry {
                actor_id: *actor_id,
                attack_range: *attack_range,
            })
            .collect::<Vec<_>>();
        actor_attack_ranges.sort_by_key(|entry| entry.actor_id);

        let mut actor_combat_behaviors = self
            .actor_combat_behaviors
            .iter()
            .map(|(actor_id, behavior)| ActorCombatBehaviorSnapshotEntry {
                actor_id: *actor_id,
                behavior: behavior.clone(),
            })
            .collect::<Vec<_>>();
        actor_combat_behaviors.sort_by_key(|entry| entry.actor_id);

        let mut actor_combat_attributes = self
            .actor_combat_attributes
            .iter()
            .map(
                |(actor_id, attributes)| ActorCombatAttributesSnapshotEntry {
                    actor_id: *actor_id,
                    attributes: attributes.clone(),
                },
            )
            .collect::<Vec<_>>();
        actor_combat_attributes.sort_by_key(|entry| entry.actor_id);

        let mut actor_resources = self
            .actor_resources
            .iter()
            .map(|(actor_id, resources)| ActorResourcesSnapshotEntry {
                actor_id: *actor_id,
                resources: resources.clone(),
            })
            .collect::<Vec<_>>();
        actor_resources.sort_by_key(|entry| entry.actor_id);

        let mut actor_loot_tables = self
            .actor_loot_tables
            .iter()
            .map(|(actor_id, loot)| ActorLootTableSnapshotEntry {
                actor_id: *actor_id,
                loot: loot.clone(),
            })
            .collect::<Vec<_>>();
        actor_loot_tables.sort_by_key(|entry| entry.actor_id);

        let mut actor_progression = self
            .actor_progression
            .iter()
            .map(|(actor_id, progression)| ActorProgressionSnapshotEntry {
                actor_id: *actor_id,
                progression: progression.clone(),
            })
            .collect::<Vec<_>>();
        actor_progression.sort_by_key(|entry| entry.actor_id);

        let mut actor_xp_rewards = self
            .actor_xp_rewards
            .iter()
            .map(|(actor_id, xp_reward)| ActorXpRewardSnapshotEntry {
                actor_id: *actor_id,
                xp_reward: *xp_reward,
            })
            .collect::<Vec<_>>();
        actor_xp_rewards.sort_by_key(|entry| entry.actor_id);

        let mut actor_skill_states = self
            .actor_skill_states
            .iter()
            .map(|(actor_id, states)| {
                let mut states = states
                    .iter()
                    .map(|(skill_id, state)| SkillRuntimeSnapshotEntry {
                        skill_id: skill_id.clone(),
                        state: state.clone(),
                    })
                    .collect::<Vec<_>>();
                states.sort_by(|left, right| left.skill_id.cmp(&right.skill_id));
                ActorSkillStateSnapshotEntry {
                    actor_id: *actor_id,
                    states,
                }
            })
            .collect::<Vec<_>>();
        actor_skill_states.sort_by_key(|entry| entry.actor_id);

        let mut active_quests = self.active_quests.values().cloned().collect::<Vec<_>>();
        active_quests.sort_by(|left, right| left.quest_id.cmp(&right.quest_id));

        let completed_quests = self.completed_quests.iter().cloned().collect::<Vec<_>>();

        let mut actor_relationships = self
            .actor_relationships
            .iter()
            .map(
                |((actor_id, target_actor_id), score)| ActorRelationshipSnapshotEntry {
                    actor_id: *actor_id,
                    target_actor_id: *target_actor_id,
                    score: *score,
                },
            )
            .collect::<Vec<_>>();
        actor_relationships.sort_by_key(|entry| (entry.actor_id, entry.target_actor_id));

        let mut actor_autonomous_movement_goals = self
            .actor_autonomous_movement_goals
            .iter()
            .map(
                |(actor_id, goal)| ActorAutonomousMovementGoalSnapshotEntry {
                    actor_id: *actor_id,
                    goal: *goal,
                },
            )
            .collect::<Vec<_>>();
        actor_autonomous_movement_goals.sort_by_key(|entry| entry.actor_id);

        let mut actor_combat_origins = self
            .actor_combat_origins
            .iter()
            .map(|(actor_id, grid)| ActorCombatOriginSnapshotEntry {
                actor_id: *actor_id,
                grid: *grid,
            })
            .collect::<Vec<_>>();
        actor_combat_origins.sort_by_key(|entry| entry.actor_id);

        let mut active_dialogues = self
            .active_dialogues
            .iter()
            .map(|(actor_id, session)| DialogueSessionSnapshotEntry {
                actor_id: *actor_id,
                session: session.clone(),
            })
            .collect::<Vec<_>>();
        active_dialogues.sort_by_key(|entry| entry.actor_id);

        SimulationStateSnapshot {
            config: self.config,
            turn: self.turn.clone(),
            group_orders: self.group_orders.save_snapshot(),
            active_actions: self.active_actions.save_snapshot(),
            actors: self.actors.save_snapshot(),
            actor_interactions,
            actor_attack_ranges,
            actor_combat_behaviors,
            actor_combat_attributes,
            actor_resources,
            actor_loot_tables,
            actor_progression,
            actor_xp_rewards,
            actor_skill_states,
            active_quests,
            completed_quests,
            actor_relationships,
            actor_autonomous_movement_goals,
            actor_combat_origins,
            active_dialogues,
            economy: self.economy.save_snapshot(),
            interaction_context: self.interaction_context.clone(),
            active_location_id: self.active_location_id.clone(),
            current_entry_point_id: self.current_entry_point_id.clone(),
            overworld_pawn_cell: self.overworld_pawn_cell,
            return_outdoor_location_id: self.return_outdoor_location_id.clone(),
            unlocked_locations: self.unlocked_locations.iter().cloned().collect(),
            active_overworld_id: self.active_overworld_id.clone(),
            grid_world: self.grid_world.save_snapshot(),
            pending_progression: self.pending_progression.iter().copied().collect(),
            next_actor_id: self.next_actor_id,
            next_registration_index: self.next_registration_index,
        }
    }

    pub(crate) fn load_snapshot(&mut self, snapshot: SimulationStateSnapshot) {
        self.config = snapshot.config;
        self.turn = snapshot.turn;
        self.group_orders.load_snapshot(snapshot.group_orders);
        self.active_actions.load_snapshot(snapshot.active_actions);
        self.actors.load_snapshot(snapshot.actors);
        self.actor_interactions = snapshot
            .actor_interactions
            .into_iter()
            .map(|entry| (entry.actor_id, entry.interaction))
            .collect();
        self.actor_attack_ranges = snapshot
            .actor_attack_ranges
            .into_iter()
            .map(|entry| (entry.actor_id, entry.attack_range))
            .collect();
        self.actor_combat_behaviors = snapshot
            .actor_combat_behaviors
            .into_iter()
            .map(|entry| (entry.actor_id, entry.behavior))
            .collect();
        self.actor_combat_attributes = snapshot
            .actor_combat_attributes
            .into_iter()
            .map(|entry| (entry.actor_id, entry.attributes))
            .collect();
        self.actor_resources = snapshot
            .actor_resources
            .into_iter()
            .map(|entry| (entry.actor_id, entry.resources))
            .collect();
        self.actor_loot_tables = snapshot
            .actor_loot_tables
            .into_iter()
            .map(|entry| (entry.actor_id, entry.loot))
            .collect();
        self.actor_progression = snapshot
            .actor_progression
            .into_iter()
            .map(|entry| (entry.actor_id, entry.progression))
            .collect();
        self.actor_xp_rewards = snapshot
            .actor_xp_rewards
            .into_iter()
            .map(|entry| (entry.actor_id, entry.xp_reward))
            .collect();
        self.actor_skill_states = snapshot
            .actor_skill_states
            .into_iter()
            .map(|entry| {
                (
                    entry.actor_id,
                    entry
                        .states
                        .into_iter()
                        .map(|state| (state.skill_id, state.state))
                        .collect(),
                )
            })
            .collect();
        self.active_quests = snapshot
            .active_quests
            .into_iter()
            .map(|quest| (quest.quest_id.clone(), quest))
            .collect();
        self.completed_quests = snapshot.completed_quests.into_iter().collect();
        self.actor_relationships = snapshot
            .actor_relationships
            .into_iter()
            .map(|entry| ((entry.actor_id, entry.target_actor_id), entry.score))
            .collect();
        self.actor_autonomous_movement_goals = snapshot
            .actor_autonomous_movement_goals
            .into_iter()
            .map(|entry| (entry.actor_id, entry.goal))
            .collect();
        self.actor_combat_origins = snapshot
            .actor_combat_origins
            .into_iter()
            .map(|entry| (entry.actor_id, entry.grid))
            .collect();
        self.active_dialogues = snapshot
            .active_dialogues
            .into_iter()
            .map(|entry| (entry.actor_id, entry.session))
            .collect();
        self.actor_runtime_actions.clear();
        self.economy.load_snapshot(snapshot.economy);
        self.interaction_context = snapshot.interaction_context;
        self.active_location_id = snapshot.active_location_id;
        self.current_entry_point_id = snapshot.current_entry_point_id;
        self.overworld_pawn_cell = snapshot.overworld_pawn_cell;
        self.return_outdoor_location_id = snapshot.return_outdoor_location_id;
        self.unlocked_locations = snapshot.unlocked_locations.into_iter().collect();
        self.active_overworld_id = snapshot.active_overworld_id;
        self.ai_controllers.clear();
        self.grid_world.load_snapshot(snapshot.grid_world);
        self.ensure_current_map_containers();
        self.pending_progression = snapshot.pending_progression.into();
        self.next_actor_id = snapshot.next_actor_id.max(1);
        self.next_registration_index = snapshot.next_registration_index;
        self.events.clear();
    }
}
