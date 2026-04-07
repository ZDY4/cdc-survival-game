use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::path::{Path, PathBuf};

use game_data::{
    GridCoord, MapDefinition, MapEntryPointDefinition, MapId, MapLevelDefinition, MapSize,
    OverworldCellDefinition, OverworldDefinition, OverworldId, OverworldLocationDefinition,
    OverworldLocationId, OverworldLocationKind, OverworldTravelRuleSet,
};
use serde_json::Value;

fn main() -> Result<(), String> {
    let repo_root = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("..")
        .join("..")
        .join("..")
        .canonicalize()
        .map_err(|error| format!("failed to resolve repo root: {error}"))?;

    let locations_path = repo_root
        .join("data")
        .join("json")
        .join("map_locations.json");
    let map_data_path = repo_root.join("data").join("json").join("map_data.json");
    let overworld_dir = repo_root.join("data").join("overworld");
    let maps_dir = repo_root.join("data").join("maps");

    let locations = read_json(&locations_path)?;
    let map_data = read_json(&map_data_path)?;

    fs::create_dir_all(&overworld_dir)
        .map_err(|error| format!("failed to create {}: {error}", overworld_dir.display()))?;

    let locations_object = locations
        .as_object()
        .ok_or_else(|| "map_locations.json must be an object".to_string())?;
    let map_data_object = map_data
        .as_object()
        .ok_or_else(|| "map_data.json must be an object".to_string())?;

    let mut location_definitions = Vec::new();
    let mut required_maps = BTreeSet::new();
    for (location_id, raw_definition) in locations_object {
        let definition = raw_definition.as_object().ok_or_else(|| {
            format!("location {location_id} definition must be an object in map_locations.json")
        })?;

        let kind = match definition
            .get("location_kind")
            .and_then(Value::as_str)
            .unwrap_or("outdoor")
            .trim()
            .to_ascii_lowercase()
            .as_str()
        {
            "interior" => OverworldLocationKind::Interior,
            "dungeon" => OverworldLocationKind::Dungeon,
            _ => OverworldLocationKind::Outdoor,
        };
        let map_id = MapId(format!("{location_id}_grid"));
        let entry_point_id = "default_entry".to_string();
        let return_entry_point_id = if kind == OverworldLocationKind::Outdoor {
            None
        } else {
            Some("outdoor_return".to_string())
        };
        let overworld_cell = parse_cell(
            definition
                .get("overworld_cell")
                .or_else(|| definition.get("world_origin_cell"))
                .unwrap_or(&Value::Null),
        );

        location_definitions.push(OverworldLocationDefinition {
            id: OverworldLocationId(location_id.clone()),
            name: definition
                .get("name")
                .and_then(Value::as_str)
                .unwrap_or(location_id)
                .to_string(),
            description: definition
                .get("description")
                .and_then(Value::as_str)
                .unwrap_or_default()
                .to_string(),
            kind,
            map_id: map_id.clone(),
            entry_point_id,
            parent_outdoor_location_id: definition
                .get("parent_outdoor_location_id")
                .and_then(Value::as_str)
                .filter(|value| !value.trim().is_empty())
                .map(|value| OverworldLocationId(value.to_string())),
            return_entry_point_id,
            default_unlocked: definition
                .get("default_unlocked")
                .and_then(Value::as_bool)
                .unwrap_or(false),
            visible: definition
                .get("overworld_visible")
                .and_then(Value::as_bool)
                .unwrap_or(kind == OverworldLocationKind::Outdoor),
            overworld_cell,
            danger_level: definition
                .get("danger_level")
                .and_then(Value::as_i64)
                .unwrap_or(0) as i32,
            icon: definition
                .get("icon")
                .and_then(Value::as_str)
                .unwrap_or_default()
                .to_string(),
            extra: BTreeMap::new(),
        });
        required_maps.insert(map_id);
    }
    location_definitions.sort_by(|left, right| left.id.cmp(&right.id));

    let walkable_cells = map_data_object
        .get("overworld_walkable_cells")
        .and_then(Value::as_array)
        .ok_or_else(|| "map_data.json overworld_walkable_cells must be an array".to_string())?
        .iter()
        .map(|value| OverworldCellDefinition {
            grid: parse_cell(value),
            terrain: "road".to_string(),
            blocked: false,
            extra: BTreeMap::new(),
        })
        .collect::<Vec<_>>();
    let size = inferred_overworld_size(&walkable_cells, &location_definitions);
    let cells = full_overworld_cells(size, &walkable_cells);

    let overworld = OverworldDefinition {
        id: OverworldId("main_overworld".into()),
        size,
        locations: location_definitions.clone(),
        cells,
        travel_rules: OverworldTravelRuleSet::default(),
    };

    let overworld_path = overworld_dir.join("main_overworld.json");
    write_json(&overworld_path, &overworld)?;

    ensure_maps(&maps_dir, &required_maps)?;

    Ok(())
}

fn ensure_maps(maps_dir: &Path, required_maps: &BTreeSet<MapId>) -> Result<(), String> {
    for map_id in required_maps {
        let path = maps_dir.join(format!("{}.json", map_id.as_str()));
        let mut definition = if path.exists() {
            serde_json::from_str::<MapDefinition>(
                &fs::read_to_string(&path)
                    .map_err(|error| format!("failed to read {}: {error}", path.display()))?,
            )
            .map_err(|error| format!("failed to parse {}: {error}", path.display()))?
        } else {
            placeholder_map_definition(map_id.as_str())
        };

        let required_entries =
            if map_id.as_str().contains("interior") || map_id.as_str().contains("dungeon") {
                vec!["default_entry".to_string(), "outdoor_return".to_string()]
            } else {
                vec!["default_entry".to_string()]
            };
        for entry_id in required_entries {
            if definition
                .entry_points
                .iter()
                .any(|entry| entry.id == entry_id)
            {
                continue;
            }
            definition.entry_points.push(MapEntryPointDefinition {
                id: entry_id.clone(),
                grid: GridCoord::new(1, definition.default_level, 1),
                facing: None,
                extra: BTreeMap::new(),
            });
        }
        definition
            .entry_points
            .sort_by(|left, right| left.id.cmp(&right.id));
        write_json(&path, &definition)?;
    }
    Ok(())
}

fn placeholder_map_definition(map_id: &str) -> MapDefinition {
    MapDefinition {
        id: MapId(map_id.to_string()),
        name: map_id.replace('_', " "),
        size: MapSize {
            width: 12,
            height: 12,
        },
        default_level: 0,
        levels: vec![MapLevelDefinition {
            y: 0,
            cells: Vec::new(),
        }],
        entry_points: vec![MapEntryPointDefinition {
            id: "default_entry".into(),
            grid: GridCoord::new(1, 0, 1),
            facing: None,
            extra: BTreeMap::new(),
        }],
        objects: Vec::new(),
    }
}

fn parse_cell(value: &Value) -> GridCoord {
    let Some(values) = value.as_array() else {
        return GridCoord::new(0, 0, 0);
    };
    let x = values.first().and_then(Value::as_i64).unwrap_or(0) as i32;
    let z = values.get(1).and_then(Value::as_i64).unwrap_or(0) as i32;
    GridCoord::new(x, 0, z)
}

fn inferred_overworld_size(
    walkable_cells: &[OverworldCellDefinition],
    locations: &[OverworldLocationDefinition],
) -> MapSize {
    let max_x = walkable_cells
        .iter()
        .map(|cell| cell.grid.x)
        .chain(locations.iter().map(|location| location.overworld_cell.x))
        .max()
        .unwrap_or(0)
        .max(0) as u32;
    let max_z = walkable_cells
        .iter()
        .map(|cell| cell.grid.z)
        .chain(locations.iter().map(|location| location.overworld_cell.z))
        .max()
        .unwrap_or(0)
        .max(0) as u32;

    MapSize {
        width: max_x + 1,
        height: max_z + 1,
    }
}

fn full_overworld_cells(
    size: MapSize,
    walkable_cells: &[OverworldCellDefinition],
) -> Vec<OverworldCellDefinition> {
    let walkable = walkable_cells
        .iter()
        .map(|cell| (cell.grid.x, cell.grid.z))
        .collect::<BTreeSet<_>>();
    let mut cells = Vec::new();
    for z in 0..size.height as i32 {
        for x in 0..size.width as i32 {
            cells.push(OverworldCellDefinition {
                grid: GridCoord::new(x, 0, z),
                terrain: if walkable.contains(&(x, z)) {
                    "road".to_string()
                } else {
                    "wilderness".to_string()
                },
                blocked: !walkable.contains(&(x, z)),
                extra: BTreeMap::new(),
            });
        }
    }
    cells
}

fn read_json(path: &Path) -> Result<Value, String> {
    let raw = fs::read_to_string(path)
        .map_err(|error| format!("failed to read {}: {error}", path.display()))?;
    serde_json::from_str(&raw)
        .map_err(|error| format!("failed to parse {}: {error}", path.display()))
}

fn write_json(path: &Path, value: &impl serde::Serialize) -> Result<(), String> {
    let raw = serde_json::to_string_pretty(value)
        .map_err(|error| format!("failed to serialize {}: {error}", path.display()))?;
    fs::write(path, raw).map_err(|error| format!("failed to write {}: {error}", path.display()))
}
