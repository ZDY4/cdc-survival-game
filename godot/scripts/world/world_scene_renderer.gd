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
var corpse_badge_material := _unshaded_material(Color(0.76, 0.62, 0.38, 0.88))
var pickup_fallback_material := _material(Color(0.22, 0.68, 0.95))
var container_fallback_material := _material(Color(0.28, 0.74, 0.38))
var trigger_fallback_material := _material(Color(0.58, 0.42, 0.92, 0.72))
var door_closed_material := _material(Color(0.50, 0.34, 0.18))
var door_open_material := _material(Color(0.64, 0.47, 0.25))
var door_locked_material := _material(Color(0.55, 0.16, 0.12))
var actor_health_material := _unshaded_material(Color(0.24, 0.86, 0.34, 0.88))
var actor_health_missing_material := _unshaded_material(Color(0.22, 0.07, 0.06, 0.72))
var actor_ap_material := _unshaded_material(Color(0.24, 0.58, 1.0, 0.86))
var actor_ap_missing_material := _unshaded_material(Color(0.07, 0.12, 0.22, 0.62))
var status_buff_material := _unshaded_material(Color(0.43, 0.86, 0.38, 0.9))
var status_passive_material := _unshaded_material(Color(0.62, 0.72, 0.95, 0.9))
var status_debuff_material := _unshaded_material(Color(0.92, 0.22, 0.18, 0.9))
var status_generic_material := _unshaded_material(Color(0.86, 0.78, 0.36, 0.9))
var quest_offer_material := _unshaded_material(Color(1.0, 0.72, 0.20, 0.94))
var quest_turn_in_ready_material := _unshaded_material(Color(1.0, 0.84, 0.18, 0.94))
var quest_turn_in_pending_material := _unshaded_material(Color(0.34, 0.82, 1.0, 0.86))


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
	var visual_object_ids: Dictionary = {}
	if bool(options.get("load_map_visuals", _should_load_map_visuals())):
		counts["map_visuals"] = _spawn_map_scene_visuals(root, map)
		visual_object_ids = _map_visual_object_ids(root)
	counts["objects"] = _spawn_interaction_target_markers(root, map, visual_object_ids)
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


func _spawn_interaction_target_markers(root: Node3D, map: Dictionary, visual_object_ids: Dictionary = {}) -> int:
	var count: int = 0
	for group_name in ["interactive_objects", "trigger_objects", "pickup_objects"]:
		for object in _array_or_empty(map.get(group_name, [])):
			_spawn_interaction_target_marker(root, _dictionary_or_empty(object), map, visual_object_ids)
			count += 1
	return count


func _spawn_interaction_target_marker(root: Node3D, object: Dictionary, map: Dictionary, visual_object_ids: Dictionary = {}) -> void:
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
	if not bool(visual_object_ids.get(str(object.get("object_id", "")), false)):
		_add_map_object_fallback_visual(node, target_data, object, width, height)
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
		_add_actor_status_markers(node, actor_data)
		_add_actor_quest_markers(node, actor_data)
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
		_apply_corpse_meta(node, corpse_data)
		node.position = _grid_to_world(_dictionary_or_empty(corpse_data.get("grid_position", {})), 0.18)
		if not _add_corpse_model(node, corpse_data):
			_add_corpse_fallback_mesh(node)
		_add_corpse_world_markers(node, corpse_data)
		_add_pickable_box(node, Vector3(0.9, 0.5, 0.75), Vector3(0.0, 0.15, 0.0))
		root.add_child(node)
	return corpses.size()


func _apply_corpse_meta(node: Node, corpse_data: Dictionary) -> void:
	node.set_meta("corpse_container_id", str(corpse_data.get("container_id", "")))
	node.set_meta("display_name", str(corpse_data.get("display_name", "")))
	node.set_meta("source_actor_id", int(corpse_data.get("source_actor_id", 0)))
	node.set_meta("source_actor_definition_id", str(corpse_data.get("source_actor_definition_id", "")))
	node.set_meta("source_actor_kind", str(corpse_data.get("source_actor_kind", "")))
	node.set_meta("defeated_by_actor_id", int(corpse_data.get("defeated_by_actor_id", 0)))
	node.set_meta("loot_count", _array_or_empty(corpse_data.get("inventory", [])).size())
	node.set_meta("money", int(corpse_data.get("money", 0)))


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


func _add_corpse_world_markers(parent: Node3D, corpse_data: Dictionary) -> void:
	var label := Label3D.new()
	label.name = "CorpseNameLabel"
	label.text = str(corpse_data.get("display_name", corpse_data.get("container_id", "corpse")))
	label.position = Vector3(0.0, 0.42, 0.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 13
	label.modulate = Color(0.82, 0.76, 0.62, 0.9)
	label.outline_size = 4
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.78)
	_apply_corpse_meta(label, corpse_data)
	parent.add_child(label)

	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.11
	mesh.bottom_radius = 0.11
	mesh.height = 0.035
	mesh.radial_segments = 20
	var badge := MeshInstance3D.new()
	badge.name = "CorpseContainerBadge"
	badge.mesh = mesh
	badge.material_override = corpse_badge_material
	badge.position = Vector3(0.0, 0.27, 0.0)
	_apply_corpse_meta(badge, corpse_data)
	badge.set_meta("target_kind", "container")
	parent.add_child(badge)


func _add_map_object_fallback_visual(parent: Node3D, target_data: Dictionary, object: Dictionary, width: float, height: float) -> void:
	var category := _map_object_fallback_category(target_data, object)
	if category.is_empty() or category == "door":
		return
	var visual := MeshInstance3D.new()
	visual.name = "MapObjectFallbackVisual"
	visual.mesh = _map_object_fallback_mesh(category, width, height)
	visual.material_override = _map_object_fallback_material(category)
	visual.position = _map_object_fallback_position(category)
	visual.set_meta("fallback_category", category)
	visual.set_meta("target_id", str(target_data.get("target_id", object.get("object_id", ""))))
	parent.add_child(visual)


func _map_object_fallback_category(target_data: Dictionary, object: Dictionary) -> String:
	var target_kind := str(target_data.get("kind", target_data.get("target_kind", "")))
	var object_kind := str(object.get("kind", ""))
	if target_kind == "pickup" or object_kind == "pickup":
		return "pickup"
	if target_kind == "door":
		return "door"
	if target_kind in ["enter_subscene", "enter_outdoor_location", "enter_overworld", "exit_to_outdoor", "scene_transition"] or object_kind == "trigger":
		return "trigger"
	if target_kind == "container" or object_kind == "interactive":
		return "container"
	return ""


func _map_object_fallback_mesh(category: String, width: float, height: float) -> Mesh:
	match category:
		"pickup":
			var sphere := SphereMesh.new()
			sphere.radius = 0.22
			sphere.height = 0.44
			sphere.radial_segments = 16
			sphere.rings = 8
			return sphere
		"trigger":
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = max(0.28, min(width, height) * 0.35)
			cylinder.bottom_radius = cylinder.top_radius
			cylinder.height = 0.04
			cylinder.radial_segments = 32
			return cylinder
	var box := BoxMesh.new()
	box.size = Vector3(max(0.55, width * 0.58), 0.46, max(0.55, height * 0.58))
	return box


func _map_object_fallback_material(category: String) -> StandardMaterial3D:
	match category:
		"pickup":
			return pickup_fallback_material
		"trigger":
			return trigger_fallback_material
	return container_fallback_material


func _map_object_fallback_position(category: String) -> Vector3:
	match category:
		"pickup":
			return Vector3(0.0, 0.28, 0.0)
		"trigger":
			return Vector3(0.0, 0.035, 0.0)
	return Vector3(0.0, 0.23, 0.0)


func _map_visual_object_ids(root: Node) -> Dictionary:
	var ids := {}
	var visual_root: Node = root.find_child("MapSceneVisuals", true, false)
	if visual_root == null:
		return ids
	var pending: Array[Node] = [visual_root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		for child in node.get_children():
			pending.append(child)
		if not node.has_method("to_object_definition"):
			continue
		var object_id := str(node.get("object_id"))
		if object_id.is_empty():
			continue
		var visuals_container: Node = node.get_node_or_null("Visuals")
		if visuals_container != null and visuals_container.get_child_count() > 0:
			ids[object_id] = true
	return ids


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


func _add_actor_status_markers(parent: Node3D, actor_data: Dictionary) -> void:
	_add_actor_name_label(parent, actor_data)
	_add_actor_side_badge(parent, actor_data)
	_add_actor_resource_bar(parent, actor_data, "health", 0.98, _actor_health_ratio(actor_data), actor_health_material, actor_health_missing_material)
	_add_actor_resource_bar(parent, actor_data, "ap", 0.86, _actor_ap_ratio(actor_data), actor_ap_material, actor_ap_missing_material)
	_add_actor_status_effect_icons(parent, actor_data)


func _add_actor_name_label(parent: Node3D, actor_data: Dictionary) -> void:
	var label := Label3D.new()
	label.name = "ActorNameLabel"
	label.text = str(actor_data.get("display_name", actor_data.get("definition_id", "actor")))
	label.position = Vector3(0.0, 1.14, 0.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 16
	label.modulate = _actor_side_color(str(actor_data.get("side", "")))
	label.outline_size = 4
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.72)
	label.set_meta("actor_id", int(actor_data.get("actor_id", 0)))
	label.set_meta("display_name", label.text)
	parent.add_child(label)


func _add_actor_side_badge(parent: Node3D, actor_data: Dictionary) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 0.09
	mesh.height = 0.18
	mesh.radial_segments = 12
	mesh.rings = 6
	var badge := MeshInstance3D.new()
	badge.name = "ActorSideBadge"
	badge.mesh = mesh
	badge.material_override = _unshaded_material(_actor_side_color(str(actor_data.get("side", ""))))
	badge.position = Vector3(-0.34, 1.02, 0.0)
	badge.set_meta("actor_id", int(actor_data.get("actor_id", 0)))
	badge.set_meta("side", str(actor_data.get("side", "")))
	parent.add_child(badge)


func _add_actor_resource_bar(parent: Node3D, actor_data: Dictionary, resource_id: String, y: float, ratio: float, fill_material: StandardMaterial3D, missing_material: StandardMaterial3D) -> void:
	var container := Node3D.new()
	container.name = "Actor%sBar" % resource_id.capitalize()
	container.position = Vector3(0.0, y, 0.0)
	container.set_meta("actor_id", int(actor_data.get("actor_id", 0)))
	container.set_meta("resource_id", resource_id)
	container.set_meta("ratio", ratio)
	_add_actor_bar_segment(container, "Missing", 1.0, missing_material, 0.0)
	_add_actor_bar_segment(container, "Fill", ratio, fill_material, -0.5 + ratio * 0.5)
	parent.add_child(container)


func _add_actor_bar_segment(parent: Node3D, suffix: String, ratio: float, material: StandardMaterial3D, x_offset: float) -> void:
	var width: float = max(0.001, clampf(ratio, 0.0, 1.0)) * 0.68
	var mesh := BoxMesh.new()
	mesh.size = Vector3(width, 0.045, 0.035)
	var node := MeshInstance3D.new()
	node.name = "ActorBar%s" % suffix
	node.mesh = mesh
	node.material_override = material
	node.position = Vector3(x_offset * 0.68, 0.0, 0.0)
	parent.add_child(node)


func _actor_health_ratio(actor_data: Dictionary) -> float:
	var combat: Dictionary = _dictionary_or_empty(actor_data.get("combat", {}))
	var max_hp: float = max(1.0, float(combat.get("max_hp", actor_data.get("max_hp", 1.0))))
	var hp: float = clampf(float(combat.get("hp", actor_data.get("hp", max_hp))), 0.0, max_hp)
	return hp / max_hp


func _actor_ap_ratio(actor_data: Dictionary) -> float:
	var combat: Dictionary = _dictionary_or_empty(actor_data.get("combat", {}))
	var attributes: Dictionary = _dictionary_or_empty(combat.get("attributes", {}))
	var max_ap := float(attributes.get("turn_ap_max", attributes.get("ap_max", 6.0)))
	max_ap = max(1.0, max_ap)
	return clampf(float(actor_data.get("ap", 0.0)) / max_ap, 0.0, 1.0)


func _actor_side_color(side: String) -> Color:
	match side:
		"player":
			return Color(0.33, 0.68, 1.0, 0.95)
		"hostile":
			return Color(1.0, 0.25, 0.18, 0.95)
		"friendly":
			return Color(0.35, 0.95, 0.48, 0.95)
		"neutral":
			return Color(1.0, 0.88, 0.32, 0.95)
	return Color(0.82, 0.82, 0.76, 0.95)


func _add_actor_status_effect_icons(parent: Node3D, actor_data: Dictionary) -> void:
	var combat: Dictionary = _dictionary_or_empty(actor_data.get("combat", {}))
	var active_effects: Array = _array_or_empty(combat.get("active_effects", []))
	if active_effects.is_empty():
		return
	var container := Node3D.new()
	container.name = "ActorStatusEffectIcons"
	container.position = Vector3(0.0, 0.73, 0.0)
	container.set_meta("actor_id", int(actor_data.get("actor_id", 0)))
	container.set_meta("effect_count", active_effects.size())
	var visible_count: int = min(active_effects.size(), 4)
	container.set_meta("visible_effect_count", visible_count)
	for index in range(visible_count):
		var effect: Dictionary = _dictionary_or_empty(active_effects[index])
		_add_actor_status_effect_icon(container, actor_data, effect, index, visible_count)
	parent.add_child(container)


func _add_actor_status_effect_icon(parent: Node3D, actor_data: Dictionary, effect: Dictionary, index: int, visible_count: int) -> void:
	var x_offset: float = (float(index) - float(visible_count - 1) * 0.5) * 0.18
	var mesh := SphereMesh.new()
	mesh.radius = 0.065
	mesh.height = 0.13
	mesh.radial_segments = 12
	mesh.rings = 6
	var icon := MeshInstance3D.new()
	icon.name = "ActorStatusEffectIcon_%d" % index
	icon.mesh = mesh
	icon.material_override = _status_effect_material(effect)
	icon.position = Vector3(x_offset, 0.0, 0.0)
	_apply_status_effect_meta(icon, actor_data, effect, index)
	parent.add_child(icon)

	var label := Label3D.new()
	label.name = "ActorStatusEffectLabel_%d" % index
	label.text = _status_effect_label_text(effect, index)
	label.position = Vector3(x_offset, 0.04, 0.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 9
	label.modulate = Color(0.98, 0.98, 0.92, 0.94)
	label.outline_size = 2
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.76)
	_apply_status_effect_meta(label, actor_data, effect, index)
	parent.add_child(label)


func _status_effect_material(effect: Dictionary) -> StandardMaterial3D:
	match str(effect.get("category", "")).to_lower():
		"passive":
			return status_passive_material
		"debuff", "negative":
			return status_debuff_material
		"buff", "active":
			return status_buff_material
	var source := str(effect.get("source", "")).to_lower()
	if source.contains("skill"):
		return status_buff_material
	return status_generic_material


func _status_effect_label_text(effect: Dictionary, index: int) -> String:
	var effect_id := str(effect.get("effect_id", "")).strip_edges()
	if not effect_id.is_empty():
		return effect_id.substr(0, 1).to_upper()
	return str(index + 1)


func _apply_status_effect_meta(node: Node, actor_data: Dictionary, effect: Dictionary, index: int) -> void:
	node.set_meta("actor_id", int(actor_data.get("actor_id", 0)))
	node.set_meta("effect_index", index)
	node.set_meta("effect_id", str(effect.get("effect_id", "")))
	node.set_meta("source", str(effect.get("source", "")))
	node.set_meta("skill_id", str(effect.get("skill_id", "")))
	node.set_meta("category", str(effect.get("category", "")))
	node.set_meta("level", int(effect.get("level", 0)))
	node.set_meta("duration_remaining", float(effect.get("duration_remaining", 0.0)))
	node.set_meta("is_infinite", bool(effect.get("is_infinite", false)))
	node.set_meta("modifiers", _dictionary_or_empty(effect.get("modifiers", {})).duplicate(true))


func _add_actor_quest_markers(parent: Node3D, actor_data: Dictionary) -> void:
	var quest_markers: Array = _array_or_empty(actor_data.get("quest_markers", []))
	if quest_markers.is_empty():
		return
	var primary: Dictionary = _dictionary_or_empty(quest_markers[0])
	var marker_kind := str(primary.get("kind", ""))
	var ready := bool(primary.get("ready", false))
	var color := _quest_marker_color(marker_kind, ready)
	var label := Label3D.new()
	label.name = "ActorQuestMarkerLabel"
	label.text = _quest_marker_label_text(marker_kind, ready)
	label.position = Vector3(0.34, 1.38, 0.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 26
	label.modulate = color
	label.outline_size = 5
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.82)
	_apply_quest_marker_meta(label, actor_data, primary)
	parent.add_child(label)

	var mesh := PrismMesh.new()
	mesh.size = Vector3(0.18, 0.24, 0.18)
	var icon := MeshInstance3D.new()
	icon.name = "ActorQuestMarker"
	icon.mesh = mesh
	icon.material_override = _quest_marker_material(marker_kind, ready)
	icon.position = Vector3(0.34, 1.20, 0.0)
	icon.rotation_degrees = Vector3(0.0, 45.0, 0.0)
	_apply_quest_marker_meta(icon, actor_data, primary)
	icon.set_meta("marker_count", quest_markers.size())
	parent.add_child(icon)


func _quest_marker_label_text(marker_kind: String, ready: bool) -> String:
	if marker_kind == "quest_offer":
		return "!"
	return "!" if ready else "?"


func _quest_marker_color(marker_kind: String, ready: bool) -> Color:
	if marker_kind == "quest_offer":
		return Color(1.0, 0.72, 0.20, 0.96)
	return Color(1.0, 0.84, 0.18, 0.96) if ready else Color(0.34, 0.82, 1.0, 0.92)


func _quest_marker_material(marker_kind: String, ready: bool) -> StandardMaterial3D:
	if marker_kind == "quest_offer":
		return quest_offer_material
	return quest_turn_in_ready_material if ready else quest_turn_in_pending_material


func _apply_quest_marker_meta(node: Node, actor_data: Dictionary, marker: Dictionary) -> void:
	node.set_meta("actor_id", int(actor_data.get("actor_id", 0)))
	node.set_meta("marker_kind", str(marker.get("kind", "")))
	node.set_meta("marker_status", str(marker.get("status", "")))
	node.set_meta("quest_id", str(marker.get("quest_id", "")))
	node.set_meta("quest_title", str(marker.get("quest_title", "")))
	node.set_meta("status", str(marker.get("status", "")))
	node.set_meta("ready", bool(marker.get("ready", false)))
	node.set_meta("objective_id", str(marker.get("objective_id", "")))
	node.set_meta("source_dialogue_id", str(marker.get("source_dialogue_id", "")))


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


static func _unshaded_material(color: Color) -> StandardMaterial3D:
	var material := _material(color)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	return material


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
