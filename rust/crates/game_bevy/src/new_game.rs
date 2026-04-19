use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};

use bevy_ecs::prelude::{Commands, Res, ResMut, Resource};
use game_core::{SimulationCommand, SimulationRuntime};
use game_data::{
    ActorKind, ActorId, MapId, MapLibrary, OverworldLibrary, OverworldLocationDefinition,
    OverworldLocationKind, WorldMode,
};
use serde::{Deserialize, Serialize};
use thiserror::Error;

use crate::{
    debug_seed_characters_for_map, ItemDefinitions, RuntimeContentLoadState, RuntimeScenarioSeed,
};

#[derive(Resource, Debug, Clone)]
pub struct NewGameConfigPath(pub PathBuf);

impl Default for NewGameConfigPath {
    fn default() -> Self {
        Self(PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../../data/bootstrap/new_game_default.json"))
    }
}

#[derive(Resource, Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct NewGameConfig {
    #[serde(default = "default_true")]
    pub clear_actor_loadout: bool,
    #[serde(default)]
    pub startup_map_id: String,
    #[serde(default)]
    pub start_location_id: String,
    #[serde(default)]
    pub start_entry_point_id: String,
    #[serde(default)]
    pub attributes: BTreeMap<String, i32>,
    #[serde(default)]
    pub items: Vec<NewGameItemStack>,
    #[serde(default)]
    pub ammo: Vec<NewGameItemStack>,
    #[serde(default)]
    pub equipment: Vec<NewGameEquipmentEntry>,
    #[serde(default)]
    pub unlocked_locations: Vec<String>,
    #[serde(default)]
    pub spawn_entries: Vec<NewGameSpawnEntry>,
}

impl Default for NewGameConfig {
    fn default() -> Self {
        Self {
            clear_actor_loadout: true,
            startup_map_id: String::new(),
            start_location_id: String::new(),
            start_entry_point_id: String::new(),
            attributes: BTreeMap::new(),
            items: Vec::new(),
            ammo: Vec::new(),
            equipment: Vec::new(),
            unlocked_locations: Vec::new(),
            spawn_entries: Vec::new(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct NewGameItemStack {
    #[serde(default)]
    pub item_id: u32,
    #[serde(default = "default_stack_count")]
    pub count: i32,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct NewGameEquipmentEntry {
    #[serde(default)]
    pub item_id: u32,
    #[serde(default)]
    pub slot_id: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct NewGameSpawnEntry {
    #[serde(default)]
    pub definition_id: game_data::CharacterId,
    #[serde(default)]
    pub grid_position: game_data::GridCoord,
}

#[derive(Debug, Error)]
pub enum NewGameConfigError {
    #[error("failed to read new game config {path}: {source}")]
    ReadFile {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    #[error("failed to parse new game config {path}: {source}")]
    ParseFile {
        path: PathBuf,
        #[source]
        source: serde_json::Error,
    },
}

pub fn load_new_game_config(path: impl AsRef<Path>) -> Result<NewGameConfig, NewGameConfigError> {
    let path = path.as_ref();
    if !path.exists() {
        return Ok(NewGameConfig::default());
    }

    let raw = fs::read_to_string(path).map_err(|source| NewGameConfigError::ReadFile {
        path: path.to_path_buf(),
        source,
    })?;
    serde_json::from_str(&raw).map_err(|source| NewGameConfigError::ParseFile {
        path: path.to_path_buf(),
        source,
    })
}

pub fn load_new_game_config_on_startup(
    mut commands: Commands,
    path: Res<NewGameConfigPath>,
    mut state: ResMut<RuntimeContentLoadState>,
) {
    match load_new_game_config(&path.0) {
        Ok(config) => {
            commands.insert_resource(config);
        }
        Err(error) => {
            state.record_failure("new_game_config", format!("{}: {error}", path.0.display()));
        }
    }
}

pub fn apply_new_game_seed_overrides(
    seed: &mut RuntimeScenarioSeed,
    config: &NewGameConfig,
    maps: &MapLibrary,
    overworld: &OverworldLibrary,
) -> Result<(), String> {
    if !config.unlocked_locations.is_empty() {
        seed.unlocked_locations = config.unlocked_locations.clone();
    }

    let configured_entry_point = normalized_text(&config.start_entry_point_id);

    if let Some(location_id) = normalized_text(&config.start_location_id) {
        let location = resolve_location_definition(overworld, &location_id)
            .ok_or_else(|| format!("unknown_new_game_start_location:{location_id}"))?;
        if maps.get(&location.map_id).is_none() {
            return Err(format!(
                "unknown_new_game_start_map_for_location:{}:{}",
                location_id,
                location.map_id.as_str()
            ));
        }
        apply_location_override(seed, location, configured_entry_point);
        return Ok(());
    }

    if let Some(map_id) = normalized_text(&config.startup_map_id).map(MapId) {
        if maps.get(&map_id).is_none() {
            return Err(format!("unknown_new_game_start_map:{}", map_id.as_str()));
        }
        seed.map_id = Some(map_id.clone());
        seed.start_map_id = Some(map_id.clone());
        seed.characters = debug_seed_characters_for_map(Some(&map_id));

        if let Some((location_id, entry_point_id, world_mode)) =
            resolve_location_start_for_map(overworld, &map_id)
        {
            seed.start_location_id = Some(location_id);
            seed.start_entry_point_id =
                Some(configured_entry_point.unwrap_or(entry_point_id));
            seed.start_world_mode = Some(world_mode);
        } else if let Some(entry_point_id) = configured_entry_point {
            seed.start_entry_point_id = Some(entry_point_id);
        }
    } else if let Some(entry_point_id) = configured_entry_point {
        seed.start_entry_point_id = Some(entry_point_id);
    }

    if !config.spawn_entries.is_empty() {
        seed.characters = config
            .spawn_entries
            .iter()
            .filter_map(|entry| {
                let definition_id = normalized_text(entry.definition_id.as_str())?;
                Some(crate::RuntimeSpawnEntry {
                    definition_id: game_data::CharacterId(definition_id),
                    grid_position: entry.grid_position,
                })
            })
            .collect();
    }

    Ok(())
}

pub fn apply_new_game_config(
    runtime: &mut SimulationRuntime,
    items: &ItemDefinitions,
    config: &NewGameConfig,
) -> Result<(), String> {
    let actor_id = player_actor_id(runtime).ok_or_else(|| "missing_player".to_string())?;

    if config.clear_actor_loadout {
        runtime
            .economy_mut()
            .clear_actor_loadout(actor_id)
            .map_err(|error| error.to_string())?;
    }

    for (attribute, value) in &config.attributes {
        runtime
            .economy_mut()
            .set_actor_attribute(actor_id, attribute, *value);
    }

    for entry in &config.items {
        if entry.item_id == 0 || entry.count <= 0 {
            continue;
        }
        runtime
            .economy_mut()
            .add_item(actor_id, entry.item_id, entry.count, &items.0)
            .map_err(|error| error.to_string())?;
    }

    for entry in &config.ammo {
        if entry.item_id == 0 || entry.count <= 0 {
            continue;
        }
        runtime
            .economy_mut()
            .add_ammo(actor_id, entry.item_id, entry.count, &items.0)
            .map_err(|error| error.to_string())?;
    }

    for entry in &config.equipment {
        if entry.item_id == 0 {
            continue;
        }
        let slot_id = entry.slot_id.trim();
        runtime
            .economy_mut()
            .equip_item(
                actor_id,
                entry.item_id,
                (!slot_id.is_empty()).then_some(slot_id),
                &items.0,
            )
            .map_err(|error| error.to_string())?;
    }

    for location_id in &config.unlocked_locations {
        let location_id = location_id.trim();
        if location_id.is_empty() {
            continue;
        }
        let _ = runtime.submit_command(SimulationCommand::UnlockLocation {
            location_id: location_id.to_string(),
        });
    }

    Ok(())
}

fn player_actor_id(runtime: &SimulationRuntime) -> Option<ActorId> {
    runtime
        .snapshot()
        .actors
        .iter()
        .find(|actor| actor.kind == ActorKind::Player)
        .map(|actor| actor.actor_id)
}

fn default_true() -> bool {
    true
}

fn default_stack_count() -> i32 {
    1
}

fn normalized_text(value: &str) -> Option<String> {
    let trimmed = value.trim();
    (!trimmed.is_empty()).then(|| trimmed.to_string())
}

fn resolve_location_definition<'a>(
    overworld: &'a OverworldLibrary,
    location_id: &str,
) -> Option<&'a OverworldLocationDefinition> {
    for (_, definition) in overworld.iter() {
        if let Some(location) = definition
            .locations
            .iter()
            .find(|location| location.id.as_str() == location_id)
        {
            return Some(location);
        }
    }
    None
}

fn resolve_location_start_for_map(
    overworld: &OverworldLibrary,
    map_id: &MapId,
) -> Option<(String, String, WorldMode)> {
    for (_, definition) in overworld.iter() {
        if let Some(location) = definition.locations.iter().find(|location| location.map_id == *map_id)
        {
            return Some((
                location.id.as_str().to_string(),
                location.entry_point_id.clone(),
                world_mode_for_location(location),
            ));
        }
    }
    None
}

fn apply_location_override(
    seed: &mut RuntimeScenarioSeed,
    location: &OverworldLocationDefinition,
    configured_entry_point: Option<String>,
) {
    seed.map_id = Some(location.map_id.clone());
    seed.start_map_id = Some(location.map_id.clone());
    seed.start_location_id = Some(location.id.as_str().to_string());
    seed.start_entry_point_id =
        Some(configured_entry_point.unwrap_or_else(|| location.entry_point_id.clone()));
    seed.start_world_mode = Some(world_mode_for_location(location));
    seed.characters = debug_seed_characters_for_map(Some(&location.map_id));
}

fn world_mode_for_location(location: &OverworldLocationDefinition) -> WorldMode {
    match location.kind {
        OverworldLocationKind::Interior => WorldMode::Interior,
        _ => WorldMode::Outdoor,
    }
}

#[cfg(test)]
mod tests {
    use super::{apply_new_game_seed_overrides, load_new_game_config, NewGameConfig};
    use crate::RuntimeScenarioSeed;
    use game_data::{
        CharacterId, GridCoord, MapDefinition, MapEntryPointDefinition, MapId, MapLevelDefinition,
        MapLibrary, MapSize, OverworldCellDefinition, OverworldDefinition, OverworldId,
        OverworldLibrary, OverworldLocationDefinition, OverworldLocationId,
        OverworldLocationKind, OverworldTravelRuleSet, WorldMode,
    };
    use std::fs;
    use std::collections::BTreeMap;
    use std::path::PathBuf;
    use std::time::{SystemTime, UNIX_EPOCH};

    #[test]
    fn apply_new_game_seed_overrides_replaces_unlocked_locations() {
        let (maps, overworld) = sample_libraries();
        let mut seed = RuntimeScenarioSeed {
            unlocked_locations: vec!["street_a".into(), "street_b".into()],
            ..RuntimeScenarioSeed::default()
        };
        let config = NewGameConfig {
            unlocked_locations: vec![
                "survivor_outpost_01".into(),
                "survivor_outpost_01_perimeter".into(),
            ],
            ..NewGameConfig::default()
        };

        apply_new_game_seed_overrides(&mut seed, &config, &maps, &overworld)
            .expect("seed overrides should apply");

        assert_eq!(
            seed.unlocked_locations,
            vec![
                "survivor_outpost_01".to_string(),
                "survivor_outpost_01_perimeter".to_string()
            ]
        );
    }

    #[test]
    fn apply_new_game_seed_overrides_switches_start_location_and_spawn_preset() {
        let (maps, overworld) = sample_libraries();
        let mut seed = RuntimeScenarioSeed::default();
        let config = NewGameConfig {
            start_location_id: "survivor_outpost_01_interior".into(),
            start_entry_point_id: "default_entry".into(),
            ..NewGameConfig::default()
        };

        apply_new_game_seed_overrides(&mut seed, &config, &maps, &overworld)
            .expect("seed overrides should apply");

        assert_eq!(
            seed.start_location_id.as_deref(),
            Some("survivor_outpost_01_interior")
        );
        assert_eq!(
            seed.start_map_id.as_ref().map(MapId::as_str),
            Some("survivor_outpost_01_interior")
        );
        assert_eq!(seed.start_world_mode, Some(WorldMode::Interior));
        let ids: Vec<&str> = seed
            .characters
            .iter()
            .map(|entry| entry.definition_id.as_str())
            .collect();
        assert_eq!(ids, vec!["player", "trader_lao_wang"]);
    }

    #[test]
    fn apply_new_game_seed_overrides_uses_data_driven_spawn_entries_when_present() {
        let (maps, overworld) = sample_libraries();
        let mut seed = RuntimeScenarioSeed::default();
        let config = NewGameConfig {
            spawn_entries: vec![
                super::NewGameSpawnEntry {
                    definition_id: CharacterId("player".into()),
                    grid_position: GridCoord::new(4, 0, 6),
                },
                super::NewGameSpawnEntry {
                    definition_id: CharacterId("trader_lao_wang".into()),
                    grid_position: GridCoord::new(5, 0, 6),
                },
            ],
            ..NewGameConfig::default()
        };

        apply_new_game_seed_overrides(&mut seed, &config, &maps, &overworld)
            .expect("seed overrides should apply");

        assert_eq!(seed.characters.len(), 2);
        assert_eq!(seed.characters[0].definition_id.as_str(), "player");
        assert_eq!(seed.characters[0].grid_position, GridCoord::new(4, 0, 6));
        assert_eq!(seed.characters[1].definition_id.as_str(), "trader_lao_wang");
        assert_eq!(seed.characters[1].grid_position, GridCoord::new(5, 0, 6));
    }

    #[test]
    fn load_new_game_config_accepts_realistic_json() {
        let temp_dir = temp_dir("new_game_config");
        let path = temp_dir.join("new_game_default.json");
        fs::write(
            &path,
            r#"{
  "clearActorLoadout": true,
  "startupMapId": "survivor_outpost_01",
  "startLocationId": "survivor_outpost_01",
  "startEntryPointId": "default_entry",
  "attributes": { "strength": 5, "agility": 5 },
  "items": [{ "itemId": 1008, "count": 2 }],
  "ammo": [{ "itemId": 1009, "count": 12 }],
  "equipment": [{ "itemId": 1002, "slotId": "main_hand" }],
  "unlockedLocations": ["survivor_outpost_01"],
  "spawnEntries": [
    {
      "definitionId": "player",
      "gridPosition": { "x": 0, "y": 0, "z": 0 }
    }
  ]
}"#,
        )
        .expect("config should write");

        let config = load_new_game_config(&path).expect("config should load");

        assert!(config.clear_actor_loadout);
        assert_eq!(config.startup_map_id, "survivor_outpost_01");
        assert_eq!(config.start_location_id, "survivor_outpost_01");
        assert_eq!(config.start_entry_point_id, "default_entry");
        assert_eq!(config.attributes.get("strength").copied(), Some(5));
        assert_eq!(config.items.len(), 1);
        assert_eq!(config.ammo.len(), 1);
        assert_eq!(config.equipment.len(), 1);
        assert_eq!(config.spawn_entries.len(), 1);
        assert_eq!(
            config.unlocked_locations,
            vec!["survivor_outpost_01".to_string()]
        );
    }

    fn temp_dir(label: &str) -> PathBuf {
        let suffix = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("clock should be monotonic")
            .as_nanos();
        let path = std::env::temp_dir().join(format!("game_bevy_{label}_{suffix}"));
        fs::create_dir_all(&path).expect("temp dir should exist");
        path
    }

    fn sample_libraries() -> (MapLibrary, OverworldLibrary) {
        let maps = MapLibrary::from(BTreeMap::from([
            (
                MapId("survivor_outpost_01".into()),
                sample_map("survivor_outpost_01"),
            ),
            (
                MapId("survivor_outpost_01_interior".into()),
                sample_map("survivor_outpost_01_interior"),
            ),
        ]));

        let overworld = OverworldLibrary::from(BTreeMap::from([(
            OverworldId("main_overworld".into()),
            OverworldDefinition {
                id: OverworldId("main_overworld".into()),
                size: MapSize {
                    width: 1,
                    height: 1,
                },
                locations: vec![
                    sample_location("survivor_outpost_01", "survivor_outpost_01"),
                    sample_interior_location(
                        "survivor_outpost_01_interior",
                        "survivor_outpost_01_interior",
                        "survivor_outpost_01",
                    ),
                ],
                cells: vec![OverworldCellDefinition {
                    grid: GridCoord::new(0, 0, 0),
                    terrain: game_data::OverworldTerrainKind::Road,
                    blocked: false,
                    visual: None,
                    extra: BTreeMap::new(),
                }],
                travel_rules: OverworldTravelRuleSet::default(),
            },
        )]));

        (maps, overworld)
    }

    fn sample_map(id: &str) -> MapDefinition {
        MapDefinition {
            id: MapId(id.into()),
            name: id.into(),
            size: MapSize {
                width: 8,
                height: 8,
            },
            default_level: 0,
            levels: vec![MapLevelDefinition {
                y: 0,
                cells: Vec::new(),
            }],
            entry_points: vec![MapEntryPointDefinition {
                id: "default_entry".into(),
                grid: GridCoord::new(0, 0, 0),
                facing: None,
                extra: BTreeMap::new(),
            }],
            objects: Vec::new(),
        }
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
            kind: OverworldLocationKind::Interior,
            parent_outdoor_location_id: Some(OverworldLocationId(parent_outdoor_location_id.into())),
            ..sample_location(id, map_id)
        }
    }
}
