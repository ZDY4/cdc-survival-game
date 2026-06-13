class_name WorldRuntimeRoot
extends Node3D

signal world_synced(summary: Dictionary)
signal map_scene_changed(map_id: String)

const MAP_SCENE_DIR := "res://scenes/maps"
const MapSceneRootScript = preload("res://scripts/world/map_scene_root.gd")
const InteractionControllerScript = preload("res://scripts/world/runtime/interaction_controller.gd")
const ActorLayerScript = preload("res://scripts/world/runtime/actor_layer.gd")
const CorpseLayerScript = preload("res://scripts/world/runtime/corpse_layer.gd")
const WorldMarkerLayerScript = preload("res://scripts/world/runtime/world_marker_layer.gd")
const CameraRigScript = preload("res://scripts/world/runtime/camera_rig.gd")
const LightRigScript = preload("res://scripts/world/runtime/light_rig.gd")
const DebugOverlayLayerScript = preload("res://scripts/world/runtime/debug_overlay_layer.gd")

var current_map_root: MapSceneRoot
var current_map_id := ""
var interaction_controller: Node
var actor_layer: Node3D
var corpse_layer: Node3D
var world_marker_layer: Node3D
var camera_rig: Node3D
var light_rig: Node3D
var debug_overlay_layer: Node3D
var last_summary: Dictionary = {}


func _ready() -> void:
	_ensure_runtime_children()


func load_map(map_id: String) -> void:
	var normalized := map_id.strip_edges()
	if normalized.is_empty():
		push_error("WorldRuntimeRoot.load_map 缺少 map_id")
		return
	if current_map_root != null and is_instance_valid(current_map_root) and current_map_id == normalized:
		return
	var scene_path := "%s/%s.tscn" % [MAP_SCENE_DIR, normalized]
	if not ResourceLoader.exists(scene_path):
		push_error("运行时地图场景不存在: %s" % scene_path)
		return
	var packed := load(scene_path) as PackedScene
	if packed == null:
		push_error("运行时地图场景加载失败: %s" % scene_path)
		return
	var instance := packed.instantiate() as Node3D
	if instance == null:
		push_error("运行时地图场景实例化失败: %s" % scene_path)
		return
	var map_root := instance as MapSceneRoot
	if map_root == null and instance.get_script() == MapSceneRootScript:
		map_root = instance as MapSceneRoot
	if map_root == null or not instance.has_method("to_definition"):
		instance.queue_free()
		push_error("运行时地图根节点必须是 MapSceneRoot 或暴露 to_definition: %s" % scene_path)
		return
	if current_map_root != null and is_instance_valid(current_map_root):
		if current_map_root.get_parent() == self:
			remove_child(current_map_root)
		current_map_root.queue_free()
	current_map_root = map_root
	current_map_id = normalized
	instance.name = "CurrentMap"
	add_child(instance)
	move_child(instance, 0)
	map_scene_changed.emit(normalized)


func current_map() -> MapSceneRoot:
	return current_map_root


func sync_world(world_snapshot: Dictionary, runtime_snapshot: Dictionary = {}, options: Dictionary = {}) -> Dictionary:
	_ensure_runtime_children()
	var map_snapshot := _dictionary_or_empty(world_snapshot.get("map", {}))
	var map_id := str(map_snapshot.get("map_id", map_snapshot.get("id", ""))).strip_edges()
	if map_id.is_empty() and current_map_root != null:
		map_id = current_map_id
	if not map_id.is_empty():
		load_map(map_id)

	var counts := {
		"map_scene": 1 if current_map_root != null and is_instance_valid(current_map_root) else 0,
		"actors": 0,
		"corpses": 0,
		"markers": 0,
		"interaction_targets": 0,
		"colliders": 0,
		"lights": 0,
		"cameras": 0,
	}
	if current_map_root != null and is_instance_valid(current_map_root):
		counts["interaction_targets"] = int(interaction_controller.call("bind_map_objects", current_map_root, _dictionary_or_empty(map_snapshot.get("interaction_targets", {}))).get("bound", 0))
	counts["actors"] = int(actor_layer.call("sync_actors", _array_or_empty(world_snapshot.get("actors", []))).get("count", 0))
	counts["corpses"] = int(corpse_layer.call("sync_corpses", _array_or_empty(world_snapshot.get("corpses", []))).get("count", 0))
	counts["markers"] = int(world_marker_layer.call("sync_markers", actor_layer, corpse_layer, world_snapshot, runtime_snapshot).get("count", 0))
	counts["lights"] = int(light_rig.call("sync_lights", map_snapshot).get("count", 0))
	counts["cameras"] = int(camera_rig.call("sync_camera", map_snapshot, _camera_focus(world_snapshot), _viewport_size()).get("count", 0))
	counts["colliders"] = _pickable_body_count(self)
	last_summary = _render_count_summary(counts)
	world_synced.emit(last_summary.duplicate(true))
	return counts


func clear_world() -> void:
	if current_map_root != null and is_instance_valid(current_map_root):
		current_map_root.queue_free()
	current_map_root = null
	current_map_id = ""
	if actor_layer != null and actor_layer.has_method("clear_actors"):
		actor_layer.call("clear_actors")
	if corpse_layer != null and corpse_layer.has_method("clear_corpses"):
		corpse_layer.call("clear_corpses")
	if world_marker_layer != null and world_marker_layer.has_method("clear_markers"):
		world_marker_layer.call("clear_markers")


func snapshot() -> Dictionary:
	return {
		"map_id": current_map_id,
		"has_current_map": current_map_root != null and is_instance_valid(current_map_root),
		"summary": last_summary.duplicate(true),
	}


func render_count_summary() -> Dictionary:
	return last_summary.duplicate(true)


func _ensure_runtime_children() -> void:
	interaction_controller = _ensure_child("InteractionController", InteractionControllerScript, false)
	actor_layer = _ensure_child("ActorLayer", ActorLayerScript, true) as Node3D
	corpse_layer = _ensure_child("CorpseLayer", CorpseLayerScript, true) as Node3D
	world_marker_layer = _ensure_child("WorldMarkerLayer", WorldMarkerLayerScript, true) as Node3D
	camera_rig = _ensure_child("CameraRig", CameraRigScript, true) as Node3D
	light_rig = _ensure_child("LightRig", LightRigScript, true) as Node3D
	debug_overlay_layer = _ensure_child("DebugOverlayLayer", DebugOverlayLayerScript, true) as Node3D


func _ensure_child(child_name: String, script_resource: Script, node_3d: bool) -> Node:
	var existing := get_node_or_null(child_name)
	if existing != null:
		return existing
	var node: Node = Node3D.new() if node_3d else Node.new()
	node.name = child_name
	node.set_script(script_resource)
	add_child(node)
	return node


func _camera_focus(world_snapshot: Dictionary) -> Vector3:
	for actor in _array_or_empty(world_snapshot.get("actors", [])):
		var actor_data := _dictionary_or_empty(actor)
		if str(actor_data.get("kind", "")) == "player":
			return _grid_to_world(_dictionary_or_empty(actor_data.get("grid_position", {})), 0.5)
	var map_snapshot := _dictionary_or_empty(world_snapshot.get("map", {}))
	var size := _dictionary_or_empty(map_snapshot.get("size", {}))
	return Vector3((float(size.get("width", 1)) - 1.0) * 0.5, 0.5, (float(size.get("height", 1)) - 1.0) * 0.5)


func _grid_to_world(grid: Dictionary, y: float) -> Vector3:
	return Vector3(float(grid.get("x", 0)), y, float(grid.get("z", 0)))


func _viewport_size() -> Vector2:
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return Vector2(1440, 900)
	return Vector2(viewport.get_visible_rect().size)


func _pickable_body_count(root: Node) -> int:
	var count := 0
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node is CollisionObject3D:
			count += 1
		for child in node.get_children():
			pending.append(child)
	return count


func _render_count_summary(counts: Dictionary) -> Dictionary:
	var summary: Dictionary = counts.duplicate(true)
	var total: int = 0
	for value in counts.values():
		if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
			total += int(value)
	summary["total"] = total
	return summary


func _dictionary_or_empty(value: Variant) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}


func _array_or_empty(value: Variant) -> Array:
	return value if typeof(value) == TYPE_ARRAY else []
