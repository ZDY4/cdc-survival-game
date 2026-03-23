use std::cmp::Ordering;
use std::collections::{BinaryHeap, HashMap};

use game_data::{ActorId, GridCoord, WorldCoord};

use super::world::GridWorld;

const ORTHOGONAL_COST: i32 = 1000;
const DIAGONAL_COST: i32 = 1414;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum GridPathfindingError {
    TargetNotWalkable,
    NoPath,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct OpenNode {
    grid: GridCoord,
    f_score: i32,
}

impl Ord for OpenNode {
    fn cmp(&self, other: &Self) -> Ordering {
        other
            .f_score
            .cmp(&self.f_score)
            .then_with(|| other.grid.x.cmp(&self.grid.x))
            .then_with(|| other.grid.z.cmp(&self.grid.z))
            .then_with(|| other.grid.y.cmp(&self.grid.y))
    }
}

impl PartialOrd for OpenNode {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

pub fn find_path_world(
    world: &GridWorld,
    actor_id: Option<ActorId>,
    start: WorldCoord,
    goal: WorldCoord,
) -> Result<Vec<WorldCoord>, GridPathfindingError> {
    let path = find_path_grid(
        world,
        actor_id,
        world.world_to_grid(start),
        world.world_to_grid(goal),
    )?;
    Ok(path
        .into_iter()
        .map(|grid| world.grid_to_world(grid))
        .collect())
}

pub fn find_path_grid(
    world: &GridWorld,
    actor_id: Option<ActorId>,
    start: GridCoord,
    goal: GridCoord,
) -> Result<Vec<GridCoord>, GridPathfindingError> {
    if !world.is_walkable_for_actor(goal, actor_id) {
        return Err(GridPathfindingError::TargetNotWalkable);
    }

    if start == goal {
        return Ok(vec![start]);
    }

    let mut open = BinaryHeap::new();
    let mut came_from: HashMap<GridCoord, GridCoord> = HashMap::new();
    let mut g_score: HashMap<GridCoord, i32> = HashMap::new();

    g_score.insert(start, 0);
    open.push(OpenNode {
        grid: start,
        f_score: heuristic(start, goal),
    });

    while let Some(OpenNode { grid: current, .. }) = open.pop() {
        if current == goal {
            return Ok(reconstruct_path(&came_from, current));
        }

        let current_g = *g_score.get(&current).unwrap_or(&i32::MAX);
        for neighbor in neighbors(current) {
            if !can_traverse(world, actor_id, current, neighbor) {
                continue;
            }

            let tentative_g = current_g + movement_cost(current, neighbor);
            if tentative_g >= *g_score.get(&neighbor).unwrap_or(&i32::MAX) {
                continue;
            }

            came_from.insert(neighbor, current);
            g_score.insert(neighbor, tentative_g);
            open.push(OpenNode {
                grid: neighbor,
                f_score: tentative_g + heuristic(neighbor, goal),
            });
        }
    }

    Err(GridPathfindingError::NoPath)
}

fn neighbors(grid: GridCoord) -> [GridCoord; 8] {
    [
        GridCoord::new(grid.x + 1, grid.y, grid.z),
        GridCoord::new(grid.x - 1, grid.y, grid.z),
        GridCoord::new(grid.x, grid.y, grid.z + 1),
        GridCoord::new(grid.x, grid.y, grid.z - 1),
        GridCoord::new(grid.x + 1, grid.y, grid.z + 1),
        GridCoord::new(grid.x + 1, grid.y, grid.z - 1),
        GridCoord::new(grid.x - 1, grid.y, grid.z + 1),
        GridCoord::new(grid.x - 1, grid.y, grid.z - 1),
    ]
}

fn heuristic(a: GridCoord, b: GridCoord) -> i32 {
    let dx = (a.x - b.x).abs();
    let dz = (a.z - b.z).abs();
    let diagonal_steps = dx.min(dz);
    let straight_steps = dx.max(dz) - diagonal_steps;
    straight_steps * ORTHOGONAL_COST + diagonal_steps * DIAGONAL_COST
}

fn movement_cost(from: GridCoord, to: GridCoord) -> i32 {
    let dx = (to.x - from.x).abs();
    let dz = (to.z - from.z).abs();
    if dx == 1 && dz == 1 {
        DIAGONAL_COST
    } else {
        ORTHOGONAL_COST
    }
}

fn can_traverse(
    world: &GridWorld,
    actor_id: Option<ActorId>,
    from: GridCoord,
    to: GridCoord,
) -> bool {
    if !world.is_walkable_for_actor(to, actor_id) {
        return false;
    }

    let dx = to.x - from.x;
    let dz = to.z - from.z;
    if dx.abs() == 1 && dz.abs() == 1 {
        let horizontal = GridCoord::new(from.x + dx, from.y, from.z);
        let vertical = GridCoord::new(from.x, from.y, from.z + dz);
        if !world.is_walkable_for_actor(horizontal, actor_id) {
            return false;
        }
        if !world.is_walkable_for_actor(vertical, actor_id) {
            return false;
        }
    }

    true
}

fn reconstruct_path(
    came_from: &HashMap<GridCoord, GridCoord>,
    current: GridCoord,
) -> Vec<GridCoord> {
    let mut path = vec![current];
    let mut cursor = current;
    while let Some(previous) = came_from.get(&cursor).copied() {
        cursor = previous;
        path.push(cursor);
    }
    path.reverse();
    path
}
