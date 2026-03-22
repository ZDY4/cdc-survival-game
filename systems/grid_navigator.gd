class_name GridNavigator
extends RefCounted

const GRID_SIZE := 1.0
const ORTHOGONAL_COST := 1.0
const DIAGONAL_COST := 1.41421356237

func find_path(start_pos: Vector3, end_pos: Vector3, is_walkable: Callable, max_nodes: int = 5000) -> Array[Vector3]:
    var start_grid := world_to_grid(start_pos)
    var end_grid := world_to_grid(end_pos)
    var grid_path := find_path_grid(start_grid, end_grid, is_walkable, max_nodes)
    if grid_path.is_empty():
        return []
    var world_path: Array[Vector3] = []
    for grid_pos in grid_path:
        world_path.append(grid_to_world(grid_pos))
    return world_path

func find_path_grid(start_grid: Vector3i, end_grid: Vector3i, is_walkable: Callable, max_nodes: int = 5000) -> Array[Vector3i]:
    if not is_walkable.call(end_grid):
        push_warning("Target position not walkable: " + str(end_grid))
        return []

    var open_set: Array[Vector3i] = [start_grid]
    var came_from: Dictionary = {}
    var g_score: Dictionary = {start_grid: 0.0}
    var f_score: Dictionary = {start_grid: _heuristic(start_grid, end_grid)}
    var nodes_visited := 0

    while not open_set.is_empty():
        nodes_visited += 1
        if nodes_visited > max_nodes:
            push_warning("Pathfinding aborted: exceeded max_nodes (" + str(max_nodes) + ")")
            return []
        var current := _get_lowest_f_score(open_set, f_score)

        if current == end_grid:
            return _reconstruct_grid_path(came_from, current)

        open_set.erase(current)

        for neighbor in _get_neighbors(current):
            if not _can_traverse(current, neighbor, is_walkable):
                continue

            var tentative_g: float = g_score[current] + _movement_cost(current, neighbor)

            if not g_score.has(neighbor) or tentative_g < g_score[neighbor]:
                came_from[neighbor] = current
                g_score[neighbor] = tentative_g
                f_score[neighbor] = tentative_g + _heuristic(neighbor, end_grid)

                if not neighbor in open_set:
                    open_set.append(neighbor)

    return []

func world_to_grid(world_pos: Vector3) -> Vector3i:
    return Vector3i(
        floor(world_pos.x / GRID_SIZE),
        floor(world_pos.y / GRID_SIZE),
        floor(world_pos.z / GRID_SIZE)
    )

func grid_to_world(grid_pos: Vector3i) -> Vector3:
    return Vector3(
        grid_pos.x * GRID_SIZE + GRID_SIZE / 2.0,
        grid_pos.y * GRID_SIZE + GRID_SIZE / 2.0,
        grid_pos.z * GRID_SIZE + GRID_SIZE / 2.0
    )

func _get_neighbors(grid_pos: Vector3i) -> Array[Vector3i]:
    return [
        grid_pos + Vector3i(1, 0, 0),
        grid_pos + Vector3i(-1, 0, 0),
        grid_pos + Vector3i(0, 0, 1),
        grid_pos + Vector3i(0, 0, -1),
        grid_pos + Vector3i(1, 0, 1),
        grid_pos + Vector3i(1, 0, -1),
        grid_pos + Vector3i(-1, 0, 1),
        grid_pos + Vector3i(-1, 0, -1)
    ]

func _heuristic(a: Vector3i, b: Vector3i) -> float:
    var dx: int = abs(a.x - b.x)
    var dz: int = abs(a.z - b.z)
    var diagonal_steps: int = mini(dx, dz)
    var straight_steps: int = maxi(dx, dz) - diagonal_steps
    return float(straight_steps) * ORTHOGONAL_COST + float(diagonal_steps) * DIAGONAL_COST

func _movement_cost(from_pos: Vector3i, to_pos: Vector3i) -> float:
    var dx: int = abs(to_pos.x - from_pos.x)
    var dz: int = abs(to_pos.z - from_pos.z)
    if dx == 1 and dz == 1:
        return DIAGONAL_COST
    return ORTHOGONAL_COST

func _can_traverse(from_pos: Vector3i, to_pos: Vector3i, is_walkable: Callable) -> bool:
    if not is_walkable.call(to_pos):
        return false

    var dx: int = to_pos.x - from_pos.x
    var dz: int = to_pos.z - from_pos.z
    if abs(dx) == 1 and abs(dz) == 1:
        var horizontal_neighbor := from_pos + Vector3i(dx, 0, 0)
        var vertical_neighbor := from_pos + Vector3i(0, 0, dz)
        if not is_walkable.call(horizontal_neighbor):
            return false
        if not is_walkable.call(vertical_neighbor):
            return false

    return true

func _get_lowest_f_score(open_set: Array[Vector3i], f_score: Dictionary) -> Vector3i:
    var lowest := open_set[0]
    var lowest_score: float = f_score.get(lowest, INF)
    
    for pos in open_set:
        var score: float = f_score.get(pos, INF)
        if score < lowest_score:
            lowest = pos
            lowest_score = score
    
    return lowest

func _reconstruct_path(came_from: Dictionary, current: Vector3i) -> Array[Vector3]:
    var path: Array[Vector3] = []
    for grid_pos in _reconstruct_grid_path(came_from, current):
        path.append(grid_to_world(grid_pos))
    return path

func _reconstruct_grid_path(came_from: Dictionary, current: Vector3i) -> Array[Vector3i]:
    var path: Array[Vector3i] = [current]

    while came_from.has(current):
        current = came_from[current]
        path.insert(0, current)

    return path
