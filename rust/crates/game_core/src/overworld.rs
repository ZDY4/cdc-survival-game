use std::collections::{BTreeSet, HashMap, HashSet, VecDeque};

use game_data::{
    ActorId, GridCoord, MapDefinition, OverworldDefinition, OverworldLocationDefinition,
    OverworldLocationKind, WorldMode,
};
use serde::{Deserialize, Serialize};

pub type UnlockedLocationSet = BTreeSet<String>;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct OverworldRouteSnapshot {
    pub actor_id: ActorId,
    pub from_location_id: String,
    pub to_location_id: String,
    pub location_path: Vec<String>,
    pub cell_path: Vec<GridCoord>,
    pub travel_minutes: u32,
    pub food_cost: i32,
    pub stamina_cost: i32,
    pub risk_level: f32,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct OverworldTravelState {
    pub actor_id: ActorId,
    pub route: OverworldRouteSnapshot,
    pub remaining_minutes: u32,
    pub progressed_minutes: u32,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct LocationTransitionContext {
    pub location_id: String,
    pub map_id: String,
    pub entry_point_id: String,
    pub return_outdoor_location_id: Option<String>,
    pub return_entry_point_id: Option<String>,
    pub world_mode: WorldMode,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct OverworldStateSnapshot {
    pub overworld_id: Option<String>,
    pub active_location_id: Option<String>,
    pub active_outdoor_location_id: Option<String>,
    pub current_map_id: Option<String>,
    pub current_entry_point_id: Option<String>,
    pub current_overworld_cell: Option<GridCoord>,
    pub unlocked_locations: Vec<String>,
    pub travel: Option<OverworldTravelState>,
    pub world_mode: WorldMode,
}

pub fn location_by_id<'a>(
    definition: &'a OverworldDefinition,
    location_id: &str,
) -> Option<&'a OverworldLocationDefinition> {
    definition
        .locations
        .iter()
        .find(|location| location.id.as_str() == location_id)
}

pub fn find_entry_point<'a>(
    map: &'a MapDefinition,
    entry_point_id: &str,
) -> Option<&'a game_data::MapEntryPointDefinition> {
    map.entry_points
        .iter()
        .find(|entry_point| entry_point.id == entry_point_id)
}

pub fn world_mode_for_location_kind(kind: OverworldLocationKind) -> WorldMode {
    match kind {
        OverworldLocationKind::Outdoor => WorldMode::Outdoor,
        OverworldLocationKind::Interior => WorldMode::Interior,
        OverworldLocationKind::Dungeon => WorldMode::Dungeon,
    }
}

pub fn compute_location_route(
    definition: &OverworldDefinition,
    actor_id: ActorId,
    from_location_id: &str,
    from_cell: GridCoord,
    to_location_id: &str,
) -> Result<OverworldRouteSnapshot, String> {
    if to_location_id.trim().is_empty() {
        return Err("missing_overworld_location".to_string());
    }
    let to_location = location_by_id(definition, to_location_id)
        .ok_or_else(|| format!("unknown_location:{to_location_id}"))?;

    if from_cell == to_location.overworld_cell {
        return Ok(OverworldRouteSnapshot {
            actor_id,
            from_location_id: from_location_id.to_string(),
            to_location_id: to_location_id.to_string(),
            location_path: vec![from_location_id.to_string(), to_location_id.to_string()],
            cell_path: vec![from_cell],
            travel_minutes: 0,
            food_cost: 0,
            stamina_cost: 0,
            risk_level: 0.0,
        });
    }

    let cell_path = compute_cell_path(definition, from_cell, to_location.overworld_cell)
        .ok_or_else(|| "overworld_cell_route_unavailable".to_string())?;
    let steps = cell_path.len().saturating_sub(1) as u32;
    let total_minutes = steps.saturating_mul(5);
    let total_food = if total_minutes == 0 {
        0
    } else {
        ((total_minutes as f32) / 60.0).ceil() as i32
    };
    let total_stamina = steps as i32 * 2;
    let source_danger = location_by_id(definition, from_location_id)
        .map(|location| location.danger_level.max(0) as f32)
        .unwrap_or(0.0);
    let total_risk = (source_danger + to_location.danger_level.max(0) as f32) / 2.0;

    Ok(OverworldRouteSnapshot {
        actor_id,
        from_location_id: from_location_id.to_string(),
        to_location_id: to_location_id.to_string(),
        location_path: vec![from_location_id.to_string(), to_location_id.to_string()],
        cell_path,
        travel_minutes: total_minutes,
        food_cost: total_food,
        stamina_cost: total_stamina,
        risk_level: total_risk,
    })
}

pub fn compute_cell_path(
    definition: &OverworldDefinition,
    start: GridCoord,
    goal: GridCoord,
) -> Option<Vec<GridCoord>> {
    if start == goal {
        return Some(vec![start]);
    }

    let walkable: HashSet<GridCoord> = definition
        .walkable_cells
        .iter()
        .map(|cell| cell.grid)
        .collect();
    if !walkable.contains(&start) || !walkable.contains(&goal) {
        return None;
    }

    let mut queue = VecDeque::from([start]);
    let mut previous = HashMap::<GridCoord, GridCoord>::new();
    let mut visited = HashSet::from([start]);
    while let Some(current) = queue.pop_front() {
        for neighbor in neighbors(current) {
            if !walkable.contains(&neighbor) || !visited.insert(neighbor) {
                continue;
            }
            previous.insert(neighbor, current);
            if neighbor == goal {
                return Some(reconstruct_cell_path(previous, start, goal));
            }
            queue.push_back(neighbor);
        }
    }

    None
}

fn reconstruct_cell_path(
    previous: HashMap<GridCoord, GridCoord>,
    start: GridCoord,
    goal: GridCoord,
) -> Vec<GridCoord> {
    let mut path = vec![goal];
    let mut current = goal;
    while current != start {
        let Some(next) = previous.get(&current).copied() else {
            break;
        };
        current = next;
        path.push(current);
    }
    path.reverse();
    path
}

fn neighbors(current: GridCoord) -> [GridCoord; 4] {
    [
        GridCoord::new(current.x + 1, current.y, current.z),
        GridCoord::new(current.x - 1, current.y, current.z),
        GridCoord::new(current.x, current.y, current.z + 1),
        GridCoord::new(current.x, current.y, current.z - 1),
    ]
}

#[cfg(test)]
mod tests {
    use super::{compute_cell_path, compute_location_route, find_entry_point};
    use game_data::{
        GridCoord, MapDefinition, MapEntryPointDefinition, MapId, MapLevelDefinition, MapSize,
        OverworldCellDefinition, OverworldDefinition, OverworldEdgeDefinition, OverworldId,
        OverworldLocationDefinition, OverworldLocationId, OverworldLocationKind,
        OverworldTravelRuleSet,
    };
    use std::collections::BTreeMap;

    #[test]
    fn location_route_prefers_explicit_edge_weights() {
        let route = compute_location_route(
            &sample_overworld(),
            game_data::ActorId(1),
            "a",
            GridCoord::new(0, 0, 0),
            "c",
        )
        .expect("route should resolve");
        assert_eq!(route.location_path, vec!["a", "c"]);
        assert_eq!(route.travel_minutes, 10);
    }

    #[test]
    fn cell_path_uses_walkable_cells_only() {
        let definition = sample_overworld();
        let path = compute_cell_path(
            &definition,
            GridCoord::new(0, 0, 0),
            GridCoord::new(2, 0, 0),
        )
        .expect("cell path should resolve");
        assert_eq!(
            path,
            vec![
                GridCoord::new(0, 0, 0),
                GridCoord::new(1, 0, 0),
                GridCoord::new(2, 0, 0)
            ]
        );
    }

    #[test]
    fn entry_point_lookup_finds_named_entry() {
        let map = MapDefinition {
            id: MapId("sample".into()),
            name: "Sample".into(),
            size: MapSize {
                width: 4,
                height: 4,
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
        };

        assert!(find_entry_point(&map, "default_entry").is_some());
    }

    fn sample_overworld() -> OverworldDefinition {
        OverworldDefinition {
            id: OverworldId("main".into()),
            locations: vec![
                sample_location("a", 0, 0),
                sample_location("b", 1, 0),
                sample_location("c", 2, 0),
            ],
            edges: vec![
                sample_edge("a", "b", 10),
                sample_edge("b", "c", 5),
                sample_edge("a", "c", 30),
            ],
            walkable_cells: vec![
                OverworldCellDefinition {
                    grid: GridCoord::new(0, 0, 0),
                    terrain: "road".into(),
                    extra: BTreeMap::new(),
                },
                OverworldCellDefinition {
                    grid: GridCoord::new(1, 0, 0),
                    terrain: "road".into(),
                    extra: BTreeMap::new(),
                },
                OverworldCellDefinition {
                    grid: GridCoord::new(2, 0, 0),
                    terrain: "road".into(),
                    extra: BTreeMap::new(),
                },
            ],
            travel_rules: OverworldTravelRuleSet::default(),
        }
    }

    fn sample_location(id: &str, x: i32, z: i32) -> OverworldLocationDefinition {
        OverworldLocationDefinition {
            id: OverworldLocationId(id.into()),
            name: id.into(),
            description: String::new(),
            kind: OverworldLocationKind::Outdoor,
            map_id: MapId(format!("{id}_grid")),
            entry_point_id: "default_entry".into(),
            parent_outdoor_location_id: None,
            return_entry_point_id: None,
            default_unlocked: true,
            visible: true,
            overworld_cell: GridCoord::new(x, 0, z),
            danger_level: 0,
            icon: String::new(),
            extra: BTreeMap::new(),
        }
    }

    fn sample_edge(from: &str, to: &str, travel_minutes: u32) -> OverworldEdgeDefinition {
        OverworldEdgeDefinition {
            from: OverworldLocationId(from.into()),
            to: OverworldLocationId(to.into()),
            bidirectional: true,
            travel_minutes,
            food_cost: 1,
            stamina_cost: 2,
            risk_level: 1.0,
            route_cells: Vec::new(),
            extra: BTreeMap::new(),
        }
    }
}
