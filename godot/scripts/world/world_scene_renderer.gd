extends RefCounted

const GRID_SIZE := 1.0

var ground_material := _material(Color(0.22, 0.26, 0.23))
var object_material := _material(Color(0.47, 0.45, 0.38))
var blocking_material := _material(Color(0.54, 0.25, 0.22))
var interactive_material := _material(Color(0.22, 0.48, 0.72))
var trigger_material := _material(Color(0.86, 0.58, 0.18))
var pickup_material := _material(Color(0.38, 0.63, 0.32))
var actor_material := _material(Color(0.78, 0.78, 0.68))
var player_material := _material(Color(0.28, 0.55, 0.88))


func render_world(parent: Node3D, world_snapshot: Dictionary) -> Dictionary:
	_clear_children(parent)

	var map: Dictionary = world_snapshot.get("map", {})
	var root: Node3D = Node3D.new()
	root.name = "GeneratedWorld"
	parent.add_child(root)

	var counts: Dictionary = {
		"ground": 0,
		"objects": 0,
		"actors": 0,
		"lights": 0,
		"cameras": 0,
	}

	_spawn_ground(root, map)
	counts["ground"] = 1
	counts["objects"] = _spawn_object_markers(root, map)
	counts["actors"] = _spawn_actor_markers(root, _array_or_empty(world_snapshot.get("actors", [])))
	counts["lights"] = _spawn_lights(root)
	counts["cameras"] = _spawn_camera(root, map)

	return counts


func _spawn_ground(root: Node3D, map: Dictionary) -> void:
	var size: Dictionary = _dictionary_or_empty(map.get("size", {}))
	var width: float = max(1.0, float(size.get("width", 1)))
	var height: float = max(1.0, float(size.get("height", 1)))
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = Vector3(width * GRID_SIZE, 0.08, height * GRID_SIZE)

	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = "Ground"
	node.mesh = mesh
	node.material_override = ground_material
	node.position = Vector3((width - 1.0) * 0.5 * GRID_SIZE, -0.04, (height - 1.0) * 0.5 * GRID_SIZE)
	root.add_child(node)


func _spawn_object_markers(root: Node3D, map: Dictionary) -> int:
	var count: int = 0
	for group_name in ["interactive_objects", "trigger_objects", "pickup_objects"]:
		for object in _array_or_empty(map.get(group_name, [])):
			_spawn_object_marker(root, _dictionary_or_empty(object), _material_for_object_group(group_name))
			count += 1

	var blocking_cells: Dictionary = _dictionary_or_empty(map.get("blocking_cells", {}))
	for cell_key in blocking_cells.keys():
		_spawn_cell_marker(root, _grid_from_key(str(cell_key)), blocking_material, "BlockingCell")
		count += 1

	return count


func _spawn_object_marker(root: Node3D, object: Dictionary, material: Material) -> void:
	var anchor: Dictionary = _dictionary_or_empty(object.get("anchor", {}))
	var footprint: Dictionary = _dictionary_or_empty(object.get("footprint", {}))
	var width: float = max(1.0, float(footprint.get("width", 1)))
	var height: float = max(1.0, float(footprint.get("height", 1)))
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = Vector3(width * GRID_SIZE, 0.35, height * GRID_SIZE)

	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = "MapObject_%s" % object.get("object_id", "")
	node.mesh = mesh
	node.material_override = material
	node.set_meta("interaction_target", {
		"target_type": "map_object",
		"target_id": str(object.get("object_id", "")),
	})
	node.position = Vector3(
		(float(anchor.get("x", 0)) + (width - 1.0) * 0.5) * GRID_SIZE,
		0.18,
		(float(anchor.get("z", 0)) + (height - 1.0) * 0.5) * GRID_SIZE
	)
	root.add_child(node)


func _spawn_cell_marker(root: Node3D, grid: Dictionary, material: Material, prefix: String) -> void:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = Vector3(0.72, 0.28, 0.72)
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = "%s_%s_%s_%s" % [prefix, grid.get("x", 0), grid.get("y", 0), grid.get("z", 0)]
	node.mesh = mesh
	node.material_override = material
	node.position = _grid_to_world(grid, 0.14)
	root.add_child(node)


func _spawn_actor_markers(root: Node3D, actors: Array) -> int:
	for actor in actors:
		var actor_data: Dictionary = _dictionary_or_empty(actor)
		var mesh: CapsuleMesh = CapsuleMesh.new()
		mesh.radius = 0.28
		mesh.height = 1.1
		var node: MeshInstance3D = MeshInstance3D.new()
		node.name = "Actor_%s_%d" % [actor_data.get("definition_id", ""), int(actor_data.get("actor_id", 0))]
		node.mesh = mesh
		node.material_override = player_material if actor_data.get("kind", "") == "player" else actor_material
		node.set_meta("interaction_target", {
			"target_type": "actor",
			"actor_id": int(actor_data.get("actor_id", 0)),
		})
		node.position = _grid_to_world(_dictionary_or_empty(actor_data.get("grid_position", {})), 0.58)
		root.add_child(node)
	return actors.size()


func _spawn_lights(root: Node3D) -> int:
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-52.0, 36.0, 0.0)
	sun.light_energy = 1.4
	root.add_child(sun)
	return 1


func _spawn_camera(root: Node3D, map: Dictionary) -> int:
	var size: Dictionary = _dictionary_or_empty(map.get("size", {}))
	var width: float = float(size.get("width", 48))
	var height: float = float(size.get("height", 42))
	var center: Vector3 = Vector3(width * 0.5, 0.0, height * 0.5)
	var camera: Camera3D = Camera3D.new()
	camera.name = "WorldCamera"
	camera.transform = Transform3D(Basis(), center + Vector3(18.0, 24.0, 24.0)).looking_at(center, Vector3.UP)
	camera.fov = 48.0
	# 运行时场景由脚本动态生成，相机必须显式设为当前视角，避免启动后只有空视口。
	camera.current = true
	root.add_child(camera)
	return 1


func _grid_to_world(grid: Dictionary, y_offset: float) -> Vector3:
	return Vector3(float(grid.get("x", 0)) * GRID_SIZE, float(grid.get("y", 0)) + y_offset, float(grid.get("z", 0)) * GRID_SIZE)


func _grid_from_key(key: String) -> Dictionary:
	var parts: PackedStringArray = key.split(":")
	if parts.size() != 3:
		return {"x": 0, "y": 0, "z": 0}
	return {
		"x": int(parts[0]),
		"y": int(parts[1]),
		"z": int(parts[2]),
	}


func _material_for_object_group(group_name: String) -> Material:
	match group_name:
		"interactive_objects":
			return interactive_material
		"trigger_objects":
			return trigger_material
		"pickup_objects":
			return pickup_material
		_:
			return object_material


func _clear_children(parent: Node) -> void:
	for child in parent.get_children():
		child.queue_free()


static func _material(color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	return material


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
