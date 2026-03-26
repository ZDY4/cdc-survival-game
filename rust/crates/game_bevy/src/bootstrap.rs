use std::path::Path;

use thiserror::Error;

use crate::{
    build_runtime_from_seed, debug_seed_characters_for_map, default_debug_seed,
    load_character_definitions, load_map_definitions, load_overworld_definitions,
    load_runtime_startup_config, resolve_startup_map_id,
    CharacterDefinitions, CharacterLoadError, MapDefinitions, MapLoadError, OverworldDefinitions,
    OverworldLoadError, RuntimeBuildError, RuntimeScenarioSeed, RuntimeStartupConfig,
    RuntimeStartupConfigError,
};
use game_core::SimulationRuntime;

#[derive(Debug, Clone)]
pub struct RuntimeBootstrapBundle {
    pub character_definitions: CharacterDefinitions,
    pub map_definitions: MapDefinitions,
    pub overworld_definitions: OverworldDefinitions,
    pub runtime_startup_config: RuntimeStartupConfig,
}

#[derive(Debug, Error)]
pub enum RuntimeBootstrapError {
    #[error(transparent)]
    CharacterDefinitions(#[from] CharacterLoadError),
    #[error(transparent)]
    MapDefinitions(#[from] MapLoadError),
    #[error(transparent)]
    OverworldDefinitions(#[from] OverworldLoadError),
    #[error(transparent)]
    RuntimeStartupConfig(#[from] RuntimeStartupConfigError),
    #[error(transparent)]
    RuntimeBuild(#[from] RuntimeBuildError),
}

pub fn load_runtime_bootstrap(
    character_path: impl AsRef<Path>,
    map_path: impl AsRef<Path>,
    overworld_path: impl AsRef<Path>,
    runtime_startup_config_path: impl AsRef<Path>,
) -> Result<RuntimeBootstrapBundle, RuntimeBootstrapError> {
    Ok(RuntimeBootstrapBundle {
        character_definitions: load_character_definitions(character_path)?,
        map_definitions: load_map_definitions(map_path)?,
        overworld_definitions: load_overworld_definitions(overworld_path)?,
        runtime_startup_config: load_runtime_startup_config(runtime_startup_config_path)?,
    })
}

pub fn build_default_startup_seed(
    maps: &game_data::MapLibrary,
    overworld: &game_data::OverworldLibrary,
    startup_map: Option<game_data::MapId>,
) -> RuntimeScenarioSeed {
    let mut seed = default_debug_seed();
    let resolved_map_id = resolve_startup_map_id(maps, startup_map);
    seed.map_id = resolved_map_id.clone();
    seed.start_map_id = resolved_map_id.clone();
    seed.characters = debug_seed_characters_for_map(resolved_map_id.as_ref());

    if let Some((location_id, entry_point_id)) =
        resolve_location_start_for_map(overworld, resolved_map_id.as_ref())
    {
        seed.start_location_id = Some(location_id);
        seed.start_entry_point_id = Some(entry_point_id);
    }

    seed
}

pub fn build_runtime_from_default_startup_seed(
    bootstrap: &RuntimeBootstrapBundle,
) -> Result<SimulationRuntime, RuntimeBootstrapError> {
    let seed = build_default_startup_seed(
        &bootstrap.map_definitions.0,
        &bootstrap.overworld_definitions.0,
        bootstrap.runtime_startup_config.startup_map.clone(),
    );
    Ok(build_runtime_from_seed(
        &bootstrap.character_definitions.0,
        &bootstrap.map_definitions.0,
        &bootstrap.overworld_definitions.0,
        &seed,
    )?)
}

fn resolve_location_start_for_map(
    overworld: &game_data::OverworldLibrary,
    map_id: Option<&game_data::MapId>,
) -> Option<(String, String)> {
    let map_id = map_id?;
    for (_, definition) in overworld.iter() {
        for location in &definition.locations {
            if location.map_id == *map_id {
                return Some((
                    location.id.as_str().to_string(),
                    location.entry_point_id.clone(),
                ));
            }
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::build_default_startup_seed;
    use game_data::{
        GridCoord, MapId, MapLibrary, OverworldDefinition, OverworldId, OverworldLibrary,
        OverworldLocationDefinition, OverworldLocationId, OverworldLocationKind,
        OverworldTravelRuleSet,
    };
    use std::collections::BTreeMap;

    #[test]
    fn startup_seed_aligns_location_and_characters_with_perimeter_map() {
        let maps = MapLibrary::from(BTreeMap::from([
            (MapId("survivor_outpost_01_grid".into()), sample_map("survivor_outpost_01_grid")),
            (
                MapId("survivor_outpost_01_perimeter_grid".into()),
                sample_map("survivor_outpost_01_perimeter_grid"),
            ),
            (
                MapId("survivor_outpost_01_interior_grid".into()),
                sample_map("survivor_outpost_01_interior_grid"),
            ),
        ]));
        let overworld = sample_overworld_library();

        let seed = build_default_startup_seed(
            &maps,
            &overworld,
            Some(MapId("survivor_outpost_01_perimeter_grid".into())),
        );

        assert_eq!(
            seed.start_location_id.as_deref(),
            Some("survivor_outpost_01_perimeter")
        );
        assert_eq!(seed.start_entry_point_id.as_deref(), Some("default_entry"));
        let ids: Vec<&str> = seed
            .characters
            .iter()
            .map(|entry| entry.definition_id.as_str())
            .collect();
        assert_eq!(ids, vec!["player"]);
    }

    #[test]
    fn startup_seed_aligns_location_and_characters_with_interior_map() {
        let maps = MapLibrary::from(BTreeMap::from([
            (MapId("survivor_outpost_01_grid".into()), sample_map("survivor_outpost_01_grid")),
            (
                MapId("survivor_outpost_01_perimeter_grid".into()),
                sample_map("survivor_outpost_01_perimeter_grid"),
            ),
            (
                MapId("survivor_outpost_01_interior_grid".into()),
                sample_map("survivor_outpost_01_interior_grid"),
            ),
        ]));
        let overworld = sample_overworld_library();

        let seed = build_default_startup_seed(
            &maps,
            &overworld,
            Some(MapId("survivor_outpost_01_interior_grid".into())),
        );

        assert_eq!(
            seed.start_location_id.as_deref(),
            Some("survivor_outpost_01_interior")
        );
        let ids: Vec<&str> = seed
            .characters
            .iter()
            .map(|entry| entry.definition_id.as_str())
            .collect();
        assert_eq!(ids, vec!["player", "trader_lao_wang"]);
    }

    fn sample_map(id: &str) -> game_data::MapDefinition {
        game_data::MapDefinition {
            id: MapId(id.into()),
            name: id.into(),
            size: game_data::MapSize {
                width: 8,
                height: 8,
            },
            default_level: 0,
            levels: vec![game_data::MapLevelDefinition {
                y: 0,
                cells: Vec::new(),
            }],
            entry_points: vec![game_data::MapEntryPointDefinition {
                id: "default_entry".into(),
                grid: GridCoord::new(0, 0, 0),
                facing: None,
                extra: BTreeMap::new(),
            }],
            objects: if id == "survivor_outpost_01_perimeter_grid" {
                vec![game_data::MapObjectDefinition {
                    object_id: "spawn_walker".into(),
                    kind: game_data::MapObjectKind::AiSpawn,
                    anchor: GridCoord::new(15, 0, 4),
                    footprint: game_data::MapObjectFootprint::default(),
                    rotation: game_data::MapRotation::North,
                    blocks_movement: false,
                    blocks_sight: false,
                    props: game_data::MapObjectProps {
                        ai_spawn: Some(game_data::MapAiSpawnProps {
                            spawn_id: "spawn_walker".into(),
                            character_id: "zombie_walker".into(),
                            auto_spawn: true,
                            respawn_enabled: true,
                            respawn_delay: 24.0,
                            spawn_radius: 2.5,
                            extra: BTreeMap::new(),
                        }),
                        ..game_data::MapObjectProps::default()
                    },
                }]
            } else {
                Vec::new()
            },
        }
    }

    fn sample_overworld_library() -> OverworldLibrary {
        OverworldLibrary::from(BTreeMap::from([(
            OverworldId("main_overworld".into()),
            OverworldDefinition {
                id: OverworldId("main_overworld".into()),
                locations: vec![
                    sample_location("survivor_outpost_01", "survivor_outpost_01_grid"),
                    sample_location(
                        "survivor_outpost_01_perimeter",
                        "survivor_outpost_01_perimeter_grid",
                    ),
                    sample_interior_location(
                        "survivor_outpost_01_interior",
                        "survivor_outpost_01_interior_grid",
                        "survivor_outpost_01",
                    ),
                ],
                edges: Vec::new(),
                walkable_cells: Vec::new(),
                travel_rules: OverworldTravelRuleSet::default(),
            },
        )]))
    }

    fn sample_location(id: &str, map_id: &str) -> OverworldLocationDefinition {
        OverworldLocationDefinition {
            id: OverworldLocationId(id.into()),
            name: id.into(),
            description: String::new(),
            kind: OverworldLocationKind::Outdoor,
            map_id: MapId(map_id.into()),
            entry_point_id: "default_entry".into(),
            parent_outdoor_location_id: None,
            return_entry_point_id: None,
            default_unlocked: true,
            visible: true,
            overworld_cell: GridCoord::new(0, 0, 0),
            danger_level: 0,
            icon: String::new(),
            extra: BTreeMap::new(),
        }
    }

    fn sample_interior_location(
        id: &str,
        map_id: &str,
        parent_outdoor_location_id: &str,
    ) -> OverworldLocationDefinition {
        OverworldLocationDefinition {
            parent_outdoor_location_id: Some(OverworldLocationId(parent_outdoor_location_id.into())),
            kind: OverworldLocationKind::Interior,
            ..sample_location(id, map_id)
        }
    }
}
