class_name FogOfWarAdapter
extends Node
## Scene-level adapter that wires VisionSystem + FogOfWarSystem for 3D maps.

const VisionSystemScript = preload("res://systems/vision_system.gd")
const FogOfWarSystemScript = preload("res://systems/fog_of_war_system.gd")
const FogPostProcessControllerScript = preload("res://systems/fog_post_process_controller.gd")

@export var map_id: String = ""
@export var bounds_node: NodePath
@export var vision_radius_override: int = -1
@export var fog_color: Color = Color(0.05, 0.05, 0.05, 1.0)
@export var explored_alpha: float = 0.55
@export var unexplored_alpha: float = 0.85
@export var edge_softness: float = 0.01
@export var fog_transition_duration: float = 0.2
@export var mask_resolution_scale: int = 1

var _vision_system: Node = null
var _fog_system: Node = null
var _post_process_controller: Node = null
var _setup_attempts: int = 0
var _setup_complete: bool = false
const _MAX_ATTEMPTS := 60

func _ready() -> void:
	call_deferred("_try_setup")

func _try_setup() -> void:
	if _setup_complete:
		return

	var player := _find_player()
	if not player:
		_retry_setup("FogOfWarAdapter: Player not found")
		return

	var bounds := _resolve_bounds()
	if bounds.is_empty():
		_retry_setup("FogOfWarAdapter: Bounds not resolved")
		return

	var camera := _find_main_camera()
	if not camera:
		_retry_setup("FogOfWarAdapter: Main camera not ready")
		return

	var resolved_map_id := map_id
	if resolved_map_id.is_empty():
		var current_scene := get_tree().current_scene
		if current_scene and not current_scene.scene_file_path.is_empty():
			resolved_map_id = current_scene.scene_file_path
		else:
			resolved_map_id = name

	_vision_system = _ensure_vision_system(player)
	if not _vision_system:
		push_error("FogOfWarAdapter: VisionSystem not found on player")
		return
	_vision_system.initialize(
		player,
		Callable(GridMovementSystem, "world_to_grid"),
		Callable(GridMovementSystem, "grid_to_world"),
		Callable(self, "_get_blocker_cells")
	)
	_vision_system.set_grid_bounds(bounds)

	var radius := vision_radius_override
	if radius <= 0:
		var player_radius = player.get("vision_radius_tiles")
		if typeof(player_radius) == TYPE_INT and player_radius > 0:
			radius = player_radius
		else:
			radius = 10
	_vision_system.vision_radius = radius

	if not _fog_system:
		_fog_system = FogOfWarSystemScript.new()
		add_child(_fog_system)
	_fog_system.initialize(_vision_system, bounds, resolved_map_id, mask_resolution_scale)

	if player is Node3D:
		var world_pos: Vector3 = player.global_position
		var grid_pos: Vector3i = GridMovementSystem.world_to_grid(world_pos)
		_vision_system.update_from_grid(grid_pos)

	if not _post_process_controller:
		_post_process_controller = FogPostProcessControllerScript.new()
		add_child(_post_process_controller)

	_post_process_controller.initialize(
		camera,
		_fog_system.get_mask_texture(),
		_fog_system.get_bounds_min_xz(),
		_fog_system.get_bounds_size_xz(),
		_fog_system.get_mask_texel_size(),
		fog_color,
		explored_alpha,
		unexplored_alpha,
		edge_softness,
		fog_transition_duration
	)
	_post_process_controller.bind_fog_system(_fog_system)
	_setup_complete = true

func _retry_setup(error_message: String) -> void:
	_setup_attempts += 1
	if _setup_attempts < _MAX_ATTEMPTS:
		call_deferred("_try_setup")
	else:
		push_error(error_message)

func _find_player() -> Node3D:
	var current_scene := get_tree().current_scene
	if current_scene:
		var nodes = current_scene.find_children("*", "PlayerController", true, false)
		if nodes.size() > 0 and nodes[0] is Node3D:
			return nodes[0]
	return null

func _ensure_vision_system(player: Node) -> Node:
	if not player:
		return null
	var existing = player.find_children("*", "VisionSystem", true, false)
	if not existing.is_empty():
		return existing[0]
	var vision := VisionSystemScript.new()
	vision.name = "VisionSystem"
	player.add_child(vision)
	return vision

func _get_blocker_cells() -> Array[Vector3i]:
	var cells: Array[Vector3i] = []
	var nodes := get_tree().get_nodes_in_group("vision_blocker")
	for node in nodes:
		if node is Node3D:
			var world_pos: Vector3 = node.global_position
			cells.append(GridMovementSystem.world_to_grid(world_pos))
	return cells

func _resolve_bounds() -> Dictionary:
	if bounds_node.is_empty():
		return {}
	var node := get_node_or_null(bounds_node)
	if not node and get_parent():
		node = get_parent().get_node_or_null(bounds_node)
	if not node:
		return {}
	var world_aabb := _get_world_aabb(node)
	if world_aabb.size == Vector3.ZERO:
		return {}
	var min_pos := world_aabb.position
	var max_pos := world_aabb.position + world_aabb.size - Vector3(0.001, 0.0, 0.001)
	var min_grid: Vector3i = GridMovementSystem.world_to_grid(min_pos)
	var max_grid: Vector3i = GridMovementSystem.world_to_grid(max_pos)
	return {
		"min_x": min_grid.x,
		"max_x": max_grid.x,
		"min_z": min_grid.z,
		"max_z": max_grid.z
	}

func _get_world_aabb(node: Node) -> AABB:
	if node is MeshInstance3D and node.mesh:
		var local_aabb: AABB = node.mesh.get_aabb()
		return local_aabb * node.global_transform
	var meshes = node.find_children("*", "MeshInstance3D", true, false)
	if not meshes.is_empty():
		var mesh_node: MeshInstance3D = meshes[0]
		if mesh_node.mesh:
			var mesh_aabb: AABB = mesh_node.mesh.get_aabb()
			return mesh_aabb * mesh_node.global_transform
	return AABB()

func _find_main_camera() -> Camera3D:
	var viewport := get_viewport()
	if not viewport:
		return null
	return viewport.get_camera_3d()
