extends RefCounted

const MAP_SCENE_DIR := "res://scenes/maps"
const ASSET_SCENE_DIR := "res://assets"
const GRID_SIZE := 1.0
const BEVY_CAMERA_YAW_DEGREES := 0.0
const BEVY_CAMERA_PITCH_DEGREES := 36.0
const BEVY_CAMERA_FOV_DEGREES := 30.0
const BEVY_CAMERA_DISTANCE_PADDING_WORLD := 8.0
const BEVY_VIEWPORT_PADDING_PX := 72.0
const BEVY_HUD_RESERVED_WIDTH_PX := 620.0
const BEVY_DEFAULT_VIEWPORT_SIZE := Vector2(1440.0, 900.0)
const BEVY_DEFAULT_ZOOM_FACTOR := 1.0
const BEVY_LEVEL_PLANE_HEIGHT := GRID_SIZE * 0.5

var ground_material := _material(Color(0.22, 0.26, 0.23))
var actor_material := _material(Color(0.78, 0.78, 0.68))
var player_material := _material(Color(0.28, 0.55, 0.88))
var corpse_material := _material(Color(0.32, 0.26, 0.22))
var door_closed_material := _material(Color(0.50, 0.34, 0.18))
var door_open_material := _material(Color(0.64, 0.47, 0.25))
var door_locked_material := _material(Color(0.55, 0.16, 0.12))


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
		"corpses": 0,
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
	counts["corpses"] = _spawn_corpse_markers(root, _array_or_empty(world_snapshot.get("corpses", [])))
	counts["colliders"] = _pickable_body_count(root)
	counts["lights"] = _spawn_lights(root)
	counts["cameras"] = _spawn_camera(root, map, _camera_focus(world_snapshot), _viewport_size(parent))

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
			"target_kind": str(_dictionary_or_empty(active_targets.get(object_id, {})).get("kind", "")),
			"door": _dictionary_or_empty(_dictionary_or_empty(active_targets.get(object_id, {})).get("door", {})).duplicate(true),
		})
		_apply_door_state_visual(node, _dictionary_or_empty(active_targets.get(object_id, {})))
		_add_visual_pickable_body(node, active_targets.get(object_id, {}))

	for node in stale_targets:
		node.free()


func _add_visual_pickable_body(node: Node, target_data: Variant) -> void:
	if node.find_child("PickableBody", false, false) != null:
		return
	var node_3d := node as Node3D
	if node_3d == null:
		return
	var target: Dictionary = _dictionary_or_empty(target_data)
	var cells: Array = _array_or_empty(target.get("cells", []))
	var size := Vector3(GRID_SIZE, 0.7, GRID_SIZE)
	var center := Vector3.ZERO
	if not cells.is_empty():
		var min_x := INF
		var max_x := -INF
		var min_z := INF
		var max_z := -INF
		for cell in cells:
			var cell_data: Dictionary = _dictionary_or_empty(cell)
			var x := float(cell_data.get("x", 0.0))
			var z := float(cell_data.get("z", 0.0))
			min_x = minf(min_x, x)
			max_x = maxf(max_x, x)
			min_z = minf(min_z, z)
			max_z = maxf(max_z, z)
		size = Vector3((max_x - min_x + 1.0) * GRID_SIZE, 0.7, (max_z - min_z + 1.0) * GRID_SIZE)
		center = Vector3(((min_x + max_x) * 0.5 * GRID_SIZE) - node_3d.position.x, 0.35, ((min_z + max_z) * 0.5 * GRID_SIZE) - node_3d.position.z)
	_add_pickable_box(node_3d, size, center)


func _spawn_interaction_target_markers(root: Node3D, map: Dictionary) -> int:
	var count: int = 0
	for group_name in ["interactive_objects", "trigger_objects", "pickup_objects"]:
		for object in _array_or_empty(map.get(group_name, [])):
			_spawn_interaction_target_marker(root, _dictionary_or_empty(object), map)
			count += 1
	return count


func _spawn_interaction_target_marker(root: Node3D, object: Dictionary, map: Dictionary) -> void:
	var anchor: Dictionary = _dictionary_or_empty(object.get("anchor", {}))
	var footprint: Dictionary = _dictionary_or_empty(object.get("footprint", {}))
	var width: float = max(1.0, float(footprint.get("width", 1)))
	var height: float = max(1.0, float(footprint.get("height", 1)))

	var node: Node3D = Node3D.new()
	node.name = "MapObject_%s" % object.get("object_id", "")
	var target_data: Dictionary = _dictionary_or_empty(_dictionary_or_empty(map.get("interaction_targets", {})).get(str(object.get("object_id", "")), {}))
	node.set_meta("interaction_target", {
		"target_type": "map_object",
		"target_id": str(object.get("object_id", "")),
		"target_kind": str(target_data.get("kind", "")),
		"door": _dictionary_or_empty(target_data.get("door", {})).duplicate(true),
	})
	node.position = Vector3(
		(float(anchor.get("x", 0)) + (width - 1.0) * 0.5) * GRID_SIZE,
		0.18,
		(float(anchor.get("z", 0)) + (height - 1.0) * 0.5) * GRID_SIZE
	)
	_apply_door_state_visual(node, target_data)
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
		_add_equipment_models(node, _array_or_empty(actor_data.get("equipment_visuals", [])))
		if actor_data.get("kind", "") == "player":
			_add_player_runtime_marker(node)
		_add_pickable_capsule(node, 0.36, 1.25)
		root.add_child(node)
	return actors.size()


func _spawn_corpse_markers(root: Node3D, corpses: Array) -> int:
	for corpse in corpses:
		var corpse_data: Dictionary = _dictionary_or_empty(corpse)
		var node := Node3D.new()
		node.name = "Corpse_%s" % str(corpse_data.get("container_id", ""))
		node.set_meta("interaction_target", {
			"target_type": "map_object",
			"target_id": str(corpse_data.get("container_id", "")),
		})
		node.position = _grid_to_world(_dictionary_or_empty(corpse_data.get("grid_position", {})), 0.18)
		if not _add_corpse_model(node, corpse_data):
			_add_corpse_fallback_mesh(node)
		_add_pickable_box(node, Vector3(0.9, 0.5, 0.75), Vector3(0.0, 0.15, 0.0))
		root.add_child(node)
	return corpses.size()


func _add_corpse_model(parent: Node3D, corpse_data: Dictionary) -> bool:
	var model_asset := str(corpse_data.get("model_asset", "")).strip_edges()
	if model_asset.is_empty():
		return false
	var scene_path := "%s/%s" % [ASSET_SCENE_DIR, model_asset]
	if not ResourceLoader.exists(scene_path):
		push_warning("尸体模型资源不存在，使用 fallback mesh: %s" % scene_path)
		return false
	var packed: PackedScene = load(scene_path)
	if packed == null:
		push_warning("尸体模型资源加载失败，使用 fallback mesh: %s" % scene_path)
		return false
	var model_root := packed.instantiate()
	if model_root == null:
		push_warning("尸体模型资源实例化失败，使用 fallback mesh: %s" % scene_path)
		return false
	model_root.name = "CorpseModel"
	model_root.set_meta("model_asset", model_asset)
	model_root.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	model_root.scale = Vector3(0.92, 0.92, 0.92)
	model_root.position = Vector3(0.0, -0.08, 0.0)
	parent.add_child(model_root)
	return true


func _add_corpse_fallback_mesh(parent: Node3D) -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.72, 0.18, 0.5)
	var visual := MeshInstance3D.new()
	visual.name = "CorpseMarker"
	visual.mesh = mesh
	visual.material_override = corpse_material
	parent.add_child(visual)


func _apply_door_state_visual(parent: Node, target_data: Dictionary) -> void:
	var door: Dictionary = _dictionary_or_empty(target_data.get("door", {}))
	if door.is_empty():
		return
	var parent_3d := parent as Node3D
	if parent_3d == null:
		return
	var visual: MeshInstance3D = parent_3d.find_child("DoorStateVisual", false, false) as MeshInstance3D
	if visual == null:
		visual = MeshInstance3D.new()
		visual.name = "DoorStateVisual"
		parent_3d.add_child(visual)
	var cells: Array = _array_or_empty(door.get("cells", []))
	var footprint := _door_visual_size_from_cells(cells)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(max(0.72, footprint.x * 0.78), 0.82, 0.12)
	visual.mesh = mesh
	var is_open := bool(door.get("is_open", false))
	var locked := bool(door.get("locked", false))
	visual.material_override = door_locked_material if locked else (door_open_material if is_open else door_closed_material)
	visual.position = _door_visual_local_position(parent_3d, door, footprint)
	visual.rotation_degrees = Vector3(0.0, _door_visual_yaw_degrees(door, is_open), 0.0)
	visual.set_meta("door_id", str(door.get("door_id", door.get("object_id", ""))))
	visual.set_meta("door_is_open", is_open)
	visual.set_meta("door_locked", locked)
	visual.set_meta("door_visual_state", "locked" if locked else ("open" if is_open else "closed"))


func _door_visual_size_from_cells(cells: Array) -> Vector2:
	if cells.is_empty():
		return Vector2.ONE
	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	for cell in cells:
		var cell_data: Dictionary = _dictionary_or_empty(cell)
		var x := float(cell_data.get("x", 0.0))
		var z := float(cell_data.get("z", 0.0))
		min_x = minf(min_x, x)
		max_x = maxf(max_x, x)
		min_z = minf(min_z, z)
		max_z = maxf(max_z, z)
	return Vector2(max(1.0, max_x - min_x + 1.0), max(1.0, max_z - min_z + 1.0))


func _door_visual_local_position(parent: Node3D, door: Dictionary, footprint: Vector2) -> Vector3:
	var anchor: Dictionary = _dictionary_or_empty(door.get("anchor", {}))
	var world_x := (float(anchor.get("x", 0.0)) + (footprint.x - 1.0) * 0.5) * GRID_SIZE
	var world_z := (float(anchor.get("z", 0.0)) + (footprint.y - 1.0) * 0.5) * GRID_SIZE
	return Vector3(world_x - parent.position.x, 0.42, world_z - parent.position.z)


func _door_visual_yaw_degrees(door: Dictionary, is_open: bool) -> float:
	var base_yaw := 0.0
	match str(door.get("rotation", "")).to_lower():
		"east", "west":
			base_yaw = 90.0
		_:
			base_yaw = 0.0
	return base_yaw + (82.0 if is_open else 0.0)


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


func _add_player_runtime_marker(parent: Node3D) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.54
	mesh.bottom_radius = 0.54
	mesh.height = 0.035
	mesh.radial_segments = 48
	var material := _material(Color(0.1, 0.55, 1.0, 0.65))
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	var marker := MeshInstance3D.new()
	marker.name = "PlayerRuntimeMarker"
	marker.mesh = mesh
	marker.material_override = material
	marker.position = Vector3(0.0, -0.52, 0.0)
	parent.add_child(marker)


func _add_equipment_models(parent: Node3D, equipment_visuals: Array) -> void:
	for visual in equipment_visuals:
		var visual_data: Dictionary = _dictionary_or_empty(visual)
		var model_asset := str(visual_data.get("model_asset", "")).strip_edges()
		var slot_id := str(visual_data.get("slot_id", ""))
		if model_asset.is_empty() or slot_id.is_empty():
			continue
		var scene_path := "%s/%s" % [ASSET_SCENE_DIR, model_asset]
		if not ResourceLoader.exists(scene_path):
			push_warning("装备模型资源不存在，跳过显示: %s" % scene_path)
			continue
		var packed: PackedScene = load(scene_path)
		if packed == null:
			push_warning("装备模型资源加载失败，跳过显示: %s" % scene_path)
			continue
		var model_root := packed.instantiate()
		if model_root == null:
			push_warning("装备模型资源实例化失败，跳过显示: %s" % scene_path)
			continue
		model_root.name = "EquipmentModel_%s" % slot_id
		model_root.set_meta("slot_id", slot_id)
		model_root.set_meta("item_id", str(visual_data.get("item_id", "")))
		model_root.set_meta("model_asset", model_asset)
		model_root.position = _equipment_model_offset(slot_id)
		parent.add_child(model_root)


func _equipment_model_offset(slot_id: String) -> Vector3:
	match slot_id:
		"main_hand", "off_hand":
			return Vector3(0.38, 0.28, 0.0)
		"body":
			return Vector3(0.0, 0.18, 0.0)
		"legs":
			return Vector3(0.0, -0.18, 0.0)
		"feet":
			return Vector3(0.0, -0.42, 0.0)
		"head":
			return Vector3(0.0, 0.58, 0.0)
		"back":
			return Vector3(0.0, 0.12, 0.28)
		_:
			return Vector3.ZERO


func _spawn_lights(root: Node3D) -> int:
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-52.0, 36.0, 0.0)
	sun.light_energy = 1.4
	root.add_child(sun)
	return 1


func _spawn_camera(root: Node3D, map: Dictionary, focus_position: Vector3, viewport_size: Vector2) -> int:
	var size: Dictionary = _dictionary_or_empty(map.get("size", {}))
	var width: float = float(size.get("width", 48))
	var height: float = float(size.get("height", 42))
	var center: Vector3 = focus_position
	center.x = clampf(center.x, 0.0, max(0.0, width - 1.0))
	center.z = clampf(center.z, 0.0, max(0.0, height - 1.0))
	center.y = focus_position.y
	var distance := _bevy_camera_world_distance(width, height, viewport_size, BEVY_DEFAULT_ZOOM_FACTOR)
	var camera: Camera3D = Camera3D.new()
	camera.name = "WorldCamera"
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = BEVY_CAMERA_FOV_DEGREES
	camera.near = 0.1
	camera.far = max(distance * 8.0, 1000.0)
	camera.transform = Transform3D(Basis(), center + _bevy_camera_offset(distance)).looking_at(center, Vector3.BACK)
	camera.set_meta("focus_position", center)
	camera.set_meta("zoom_factor", BEVY_DEFAULT_ZOOM_FACTOR)
	camera.set_meta("bevy_camera_logic", true)
	camera.set_meta("map_size", Vector2(width, height))
	# 运行时场景由脚本动态生成，相机必须显式设为当前视角，避免启动后只有空视口。
	camera.current = true
	root.add_child(camera)
	return 1


func _camera_focus(world_snapshot: Dictionary) -> Vector3:
	for actor in _array_or_empty(world_snapshot.get("actors", [])):
		var actor_data: Dictionary = _dictionary_or_empty(actor)
		if actor_data.get("kind", "") == "player":
			return _grid_to_world(_dictionary_or_empty(actor_data.get("grid_position", {})), BEVY_LEVEL_PLANE_HEIGHT)
	var map: Dictionary = _dictionary_or_empty(world_snapshot.get("map", {}))
	var entries: Dictionary = _dictionary_or_empty(map.get("entry_points", {}))
	if entries.has("default_entry"):
		return _grid_to_world(_dictionary_or_empty(entries.get("default_entry", {})), BEVY_LEVEL_PLANE_HEIGHT)
	var size: Dictionary = _dictionary_or_empty(map.get("size", {}))
	return Vector3(float(size.get("width", 48)) * 0.5, BEVY_LEVEL_PLANE_HEIGHT, float(size.get("height", 42)) * 0.5)


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
		parent.remove_child(child)
		child.free()


func _bevy_camera_offset(distance: float) -> Vector3:
	var pitch: float = deg_to_rad(BEVY_CAMERA_PITCH_DEGREES)
	var yaw: float = deg_to_rad(BEVY_CAMERA_YAW_DEGREES)
	var horizontal: float = distance * cos(pitch)
	return Vector3(horizontal * sin(yaw), distance * sin(pitch), -horizontal * cos(yaw))


func _bevy_camera_world_distance(width: float, height: float, viewport_size: Vector2, zoom_factor: float) -> float:
	var world_width: float = max(1.0, width) * GRID_SIZE + BEVY_CAMERA_DISTANCE_PADDING_WORLD
	var world_depth: float = max(1.0, height) * GRID_SIZE + BEVY_CAMERA_DISTANCE_PADDING_WORLD
	var usable_width: float = max(160.0, viewport_size.x - BEVY_HUD_RESERVED_WIDTH_PX - BEVY_VIEWPORT_PADDING_PX * 2.0)
	var usable_height: float = max(160.0, viewport_size.y - BEVY_VIEWPORT_PADDING_PX * 2.0)
	var vertical_fov: float = deg_to_rad(BEVY_CAMERA_FOV_DEGREES)
	var aspect: float = max(0.1, usable_width / max(1.0, usable_height))
	var horizontal_fov: float = 2.0 * atan(tan(vertical_fov * 0.5) * aspect)
	var zoom: float = max(0.1, zoom_factor)
	var half_visible_width: float = (world_width / zoom) * 0.5
	var half_visible_depth: float = (world_depth / zoom) * 0.5
	var width_distance: float = half_visible_width / max(0.01, tan(horizontal_fov * 0.5))
	var depth_distance: float = half_visible_depth * max(0.1, sin(deg_to_rad(BEVY_CAMERA_PITCH_DEGREES))) / max(0.01, tan(vertical_fov * 0.5))
	return max(max(width_distance, depth_distance), 10.0 * GRID_SIZE)


func _viewport_size(node: Node) -> Vector2:
	var viewport := node.get_viewport()
	if viewport == null:
		return BEVY_DEFAULT_VIEWPORT_SIZE
	var size := viewport.get_visible_rect().size
	if size.x <= 0.0 or size.y <= 0.0:
		return BEVY_DEFAULT_VIEWPORT_SIZE
	return size


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
