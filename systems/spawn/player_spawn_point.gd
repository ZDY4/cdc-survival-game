@tool
class_name PlayerSpawnPoint
extends Marker3D

const GridNavigator = preload("res://systems/grid_navigator.gd")

@export var spawn_id: String = "default_spawn"

func _enter_tree() -> void:
	if Engine.is_editor_hint():
		set_process(true)
		call_deferred("_snap_marker_to_grid")

func _exit_tree() -> void:
	if Engine.is_editor_hint():
		set_process(false)

func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		return
	_snap_marker_to_grid()

func get_spawn_position() -> Vector3:
	return _snap_world_pos_to_grid(global_position)

func matches_spawn_id(candidate_spawn_id: String) -> bool:
	if candidate_spawn_id.strip_edges().is_empty():
		return false
	return spawn_id.strip_edges() == candidate_spawn_id.strip_edges()

func _snap_marker_to_grid() -> void:
	if not is_inside_tree():
		return

	var snapped_world_pos: Vector3 = _snap_world_pos_to_grid(global_position)
	if global_position.is_equal_approx(snapped_world_pos):
		return
	global_position = snapped_world_pos

func _snap_world_pos_to_grid(world_pos: Vector3) -> Vector3:
	var grid_size: float = GridNavigator.GRID_SIZE
	return Vector3(
		floor(world_pos.x / grid_size) * grid_size + grid_size * 0.5,
		world_pos.y,
		floor(world_pos.z / grid_size) * grid_size + grid_size * 0.5
	)
