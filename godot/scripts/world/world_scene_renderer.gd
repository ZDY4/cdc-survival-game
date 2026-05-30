extends RefCounted

const MAP_SCENE_DIR := "res://scenes/maps"
const ASSET_SCENE_DIR := "res://assets"
const GRID_SIZE := 1.0

var ground_material := _material(Color(0.22, 0.26, 0.23))
var actor_material := _material(Color(0.78, 0.78, 0.68))
var player_material := _material(Color(0.28, 0.55, 0.88))


func render_world(parent: Node3D, world_snapshot: Dictionary, options: Dictionary = {}) -> Dictionary:
	_clear_children(parent)

	var map: Dictionary = world_snapshot.get("map", {})
	var root: Node3D = Node3D.new()
	root.name = "GeneratedWorld"
	parent.add_child(root)

	var counts: Dictionary = {
		"ground": 0,
		"map_visuals": 0,
		"objects": 0,
		"actors": 0,
		"colliders": 0,
		"lights": 0,
		"cameras": 0,
	}

	_spawn_ground(root, map)
	counts["ground"] = 1
	if bool(options.get("load_map_visuals", _should_load_map_visuals())):
		counts["map_visuals"] = _spawn_map_scene_visuals(root, map)
	counts["objects"] = _spawn_interaction_target_markers(root, map)
	counts["actors"] = _spawn_actor_markers(root, _array_or_empty(world_snapshot.get("actors", [])))
	counts["colliders"] = _pickable_body_count(root)
	counts["lights"] = _spawn_lights(root)
	counts["cameras"] = _spawn_camera(root, map, _camera_focus(world_snapshot))

	return counts


func _should_load_map_visuals() -> bool:
	# Headless editor import 会初始化 dock；此时实例化 glTF 场景可能触发编辑器弹窗，视觉层留给运行时和正常 editor 视口加载。
	return not (Engine.is_editor_hint() and DisplayServer.get_name() == "headless")


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

	var body := StaticBody3D.new()
	body.name = "GroundPicker"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(width * GRID_SIZE, 0.12, height * GRID_SIZE)
	shape.shape = box
	body.add_child(shape)
	body.position = node.position
	root.add_child(body)


func _spawn_map_scene_visuals(root: Node3D, map: Dictionary) -> int:
	var map_id := str(map.get("map_id", ""))
	if map_id.is_empty():
		push_warning("运行时地图缺少 map_id，无法加载 Godot 地图场景视觉层")
		return 0

	var scene_path := "%s/%s.tscn" % [MAP_SCENE_DIR, map_id]
	if not ResourceLoader.exists(scene_path):
		push_warning("运行时地图场景不存在，回退到基础地面: %s" % scene_path)
		return 0

	var packed: PackedScene = load(scene_path)
	if packed == null:
		push_warning("运行时地图场景加载失败: %s" % scene_path)
		return 0

	var visual_root := packed.instantiate()
	if visual_root == null:
		push_warning("运行时地图场景实例化失败: %s" % scene_path)
		return 0

	visual_root.name = "MapSceneVisuals"
	_prepare_visual_interaction_targets(visual_root, map)
	root.add_child(visual_root)
	return 1


func _prepare_visual_interaction_targets(root: Node, map: Dictionary) -> void:
	var active_targets: Dictionary = _dictionary_or_empty(map.get("interaction_targets", {}))
	var stale_targets: Array[Node] = []
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		for child in node.get_children():
			pending.append(child)
		if not node.has_method("to_object_definition"):
			continue

		var object_id := str(node.get("object_id"))
		var kind := str(node.get("kind"))
		if object_id.is_empty() or not ["interactive", "trigger", "pickup"].has(kind):
			continue
		if not active_targets.has(object_id):
			stale_targets.append(node)
			continue

		# 视觉对象本身也携带交互元数据，后续接鼠标拾取时不用再依赖调试方块。
		node.set_meta("interaction_target", {
			"target_type": "map_object",
			"target_id": object_id,
		})

	for node in stale_targets:
		node.free()


func _spawn_interaction_target_markers(root: Node3D, map: Dictionary) -> int:
	var count: int = 0
	for group_name in ["interactive_objects", "trigger_objects", "pickup_objects"]:
		for object in _array_or_empty(map.get(group_name, [])):
			_spawn_interaction_target_marker(root, _dictionary_or_empty(object))
			count += 1
	return count


func _spawn_interaction_target_marker(root: Node3D, object: Dictionary) -> void:
	var anchor: Dictionary = _dictionary_or_empty(object.get("anchor", {}))
	var footprint: Dictionary = _dictionary_or_empty(object.get("footprint", {}))
	var width: float = max(1.0, float(footprint.get("width", 1)))
	var height: float = max(1.0, float(footprint.get("height", 1)))

	var node: Node3D = Node3D.new()
	node.name = "MapObject_%s" % object.get("object_id", "")
	node.set_meta("interaction_target", {
		"target_type": "map_object",
		"target_id": str(object.get("object_id", "")),
	})
	node.position = Vector3(
		(float(anchor.get("x", 0)) + (width - 1.0) * 0.5) * GRID_SIZE,
		0.18,
		(float(anchor.get("z", 0)) + (height - 1.0) * 0.5) * GRID_SIZE
	)
	_add_pickable_box(node, Vector3(width * GRID_SIZE, 0.6, height * GRID_SIZE), Vector3(0.0, 0.25, 0.0))
	root.add_child(node)


func _spawn_actor_markers(root: Node3D, actors: Array) -> int:
	for actor in actors:
		var actor_data: Dictionary = _dictionary_or_empty(actor)
		var node: Node3D = Node3D.new()
		node.name = "Actor_%s_%d" % [actor_data.get("definition_id", ""), int(actor_data.get("actor_id", 0))]
		node.set_meta("interaction_target", {
			"target_type": "actor",
			"actor_id": int(actor_data.get("actor_id", 0)),
		})
		node.position = _grid_to_world(_dictionary_or_empty(actor_data.get("grid_position", {})), 0.58)
		if not _add_actor_model(node, actor_data):
			_add_actor_fallback_mesh(node, actor_data)
		_add_pickable_capsule(node, 0.36, 1.25)
		root.add_child(node)
	return actors.size()


func _add_actor_model(parent: Node3D, actor_data: Dictionary) -> bool:
	var model_asset := str(actor_data.get("model_asset", "")).strip_edges()
	if model_asset.is_empty():
		return false
	var scene_path := "%s/%s" % [ASSET_SCENE_DIR, model_asset]
	if not ResourceLoader.exists(scene_path):
		push_warning("角色模型资源不存在，使用 fallback mesh: %s" % scene_path)
		return false
	var packed: PackedScene = load(scene_path)
	if packed == null:
		push_warning("角色模型资源加载失败，使用 fallback mesh: %s" % scene_path)
		return false
	var model_root := packed.instantiate()
	if model_root == null:
		push_warning("角色模型资源实例化失败，使用 fallback mesh: %s" % scene_path)
		return false
	model_root.name = "ActorModel"
	model_root.set_meta("model_asset", model_asset)
	parent.add_child(model_root)
	return true


func _add_actor_fallback_mesh(parent: Node3D, actor_data: Dictionary) -> void:
	var mesh: CapsuleMesh = CapsuleMesh.new()
	mesh.radius = 0.28
	mesh.height = 1.1
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = "ActorFallbackMesh"
	node.mesh = mesh
	node.material_override = player_material if actor_data.get("kind", "") == "player" else actor_material
	parent.add_child(node)


func _spawn_lights(root: Node3D) -> int:
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-52.0, 36.0, 0.0)
	sun.light_energy = 1.4
	root.add_child(sun)
	return 1


func _spawn_camera(root: Node3D, map: Dictionary, focus_position: Vector3) -> int:
	var size: Dictionary = _dictionary_or_empty(map.get("size", {}))
	var width: float = float(size.get("width", 48))
	var height: float = float(size.get("height", 42))
	var center: Vector3 = focus_position
	center.x = clampf(center.x, 0.0, max(0.0, width - 1.0))
	center.z = clampf(center.z, 0.0, max(0.0, height - 1.0))
	var camera: Camera3D = Camera3D.new()
	camera.name = "WorldCamera"
	camera.transform = Transform3D(Basis(), center + Vector3(10.0, 16.0, 14.0)).looking_at(center, Vector3.UP)
	camera.fov = 52.0
	camera.set_meta("focus_position", center)
	# 运行时场景由脚本动态生成，相机必须显式设为当前视角，避免启动后只有空视口。
	camera.current = true
	root.add_child(camera)
	return 1


func _camera_focus(world_snapshot: Dictionary) -> Vector3:
	for actor in _array_or_empty(world_snapshot.get("actors", [])):
		var actor_data: Dictionary = _dictionary_or_empty(actor)
		if actor_data.get("kind", "") == "player":
			return _grid_to_world(_dictionary_or_empty(actor_data.get("grid_position", {})), 0.0)
	var map: Dictionary = _dictionary_or_empty(world_snapshot.get("map", {}))
	var entries: Dictionary = _dictionary_or_empty(map.get("entry_points", {}))
	if entries.has("default_entry"):
		return _grid_to_world(_dictionary_or_empty(entries.get("default_entry", {})), 0.0)
	var size: Dictionary = _dictionary_or_empty(map.get("size", {}))
	return Vector3(float(size.get("width", 48)) * 0.5, 0.0, float(size.get("height", 42)) * 0.5)


func _grid_to_world(grid: Dictionary, y_offset: float) -> Vector3:
	return Vector3(float(grid.get("x", 0)) * GRID_SIZE, float(grid.get("y", 0)) + y_offset, float(grid.get("z", 0)) * GRID_SIZE)


func _add_pickable_box(parent: Node3D, size: Vector3, local_position: Vector3 = Vector3.ZERO) -> void:
	var body := StaticBody3D.new()
	body.name = "PickableBody"
	body.set_meta("interaction_target", parent.get_meta("interaction_target"))
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = local_position
	parent.add_child(body)


func _add_pickable_capsule(parent: Node3D, radius: float, height: float) -> void:
	var body := StaticBody3D.new()
	body.name = "PickableBody"
	body.set_meta("interaction_target", parent.get_meta("interaction_target"))
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = radius
	capsule.height = height
	shape.shape = capsule
	body.add_child(shape)
	parent.add_child(body)


func _pickable_body_count(root: Node) -> int:
	var count := 0
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node is StaticBody3D:
			count += 1
		for child in node.get_children():
			pending.append(child)
	return count


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
