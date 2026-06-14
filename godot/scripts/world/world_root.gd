extends Node3D

const WorldRuntimeRootScene = preload("res://scenes/world/world_runtime_root.tscn")
const WorldRuntimeRootScript = preload("res://scripts/world/runtime/world_runtime_root.gd")
const FogOverlayController = preload("res://scripts/world/fog_overlay_controller.gd")
const DebugOverlayController = preload("res://scripts/world/debug_overlay_controller.gd")

var world_container: Node3D
var runtime_root: Node3D
var fog_overlay: ColorRect
var fog_overlay_controller: RefCounted = FogOverlayController.new()
var debug_overlay_controller: RefCounted = DebugOverlayController.new()
var last_render_counts: Dictionary = {}
var render_sequence: int = 0


func ensure_world_container() -> Node3D:
	if runtime_root != null and is_instance_valid(runtime_root):
		world_container = runtime_root
		return runtime_root
	runtime_root = get_node_or_null("WorldRuntimeRoot") as Node3D
	if runtime_root == null:
		runtime_root = WorldRuntimeRootScene.instantiate() as Node3D
		if runtime_root == null:
			runtime_root = Node3D.new()
			runtime_root.set_script(WorldRuntimeRootScript)
		runtime_root.name = "WorldRuntimeRoot"
		add_child(runtime_root)
	world_container = runtime_root
	return runtime_root


func world_container_node() -> Node3D:
	return ensure_world_container()


func fog_overlay_node() -> ColorRect:
	return fog_overlay


func apply_world_snapshot(world_snapshot: Dictionary, runtime_snapshot: Dictionary = {}, options: Dictionary = {}) -> Dictionary:
	var container := ensure_world_container()
	var counts: Dictionary = {}
	if container.has_method("sync_world"):
		counts = _dictionary_or_empty(container.call("sync_world", world_snapshot, runtime_snapshot, options))
	last_render_counts = _render_count_summary(counts)
	render_sequence += 1
	return counts


func apply_runtime_snapshot(world_snapshot: Dictionary, runtime_snapshot: Dictionary = {}, debug_overlay_mode: String = "off", render_world: bool = true, options: Dictionary = {}) -> Dictionary:
	var counts: Dictionary = {}
	if render_world:
		counts = apply_world_snapshot(world_snapshot, runtime_snapshot, options)
	refresh_fog(world_snapshot, runtime_snapshot)
	refresh_debug_overlay(debug_overlay_mode, world_snapshot, runtime_snapshot)
	return {
		"rendered": render_world,
		"counts": counts,
		"world_container": ensure_world_container(),
		"fog_overlay": fog_overlay,
		"debug_overlay": debug_overlay_snapshot(),
	}


func refresh_fog(world_snapshot: Dictionary, runtime_snapshot: Dictionary) -> void:
	if world_snapshot.is_empty():
		return
	fog_overlay = fog_overlay_controller.ensure_overlay(self, _dictionary_or_empty(world_snapshot.get("map", {})), runtime_snapshot)


func refresh_debug_overlay(mode: String, world_snapshot: Dictionary, runtime_snapshot: Dictionary = {}) -> void:
	var container := ensure_world_container()
	debug_overlay_controller.apply_overlay(container, mode, _dictionary_or_empty(world_snapshot.get("map", {})), runtime_snapshot)


func debug_overlay_snapshot() -> Dictionary:
	if debug_overlay_controller != null and debug_overlay_controller.has_method("snapshot"):
		return debug_overlay_controller.snapshot()
	return {"active": false, "mode": "off", "cell_count": 0}


func runtime_world_snapshot() -> Dictionary:
	var container := ensure_world_container()
	if container != null and container.has_method("snapshot"):
		return _dictionary_or_empty(container.call("snapshot"))
	return {"has_current_map": false}


func camera_follow_snapshot() -> Dictionary:
	var container := ensure_world_container()
	if container != null and container.has_method("camera_follow_snapshot"):
		return _dictionary_or_empty(container.call("camera_follow_snapshot"))
	return {"has_camera": false, "reason": "runtime_camera_missing"}


func render_count_summary() -> Dictionary:
	return last_render_counts.duplicate(true)


func _render_count_summary(counts: Dictionary) -> Dictionary:
	var summary: Dictionary = counts.duplicate(true)
	var total := 0
	for value in counts.values():
		if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
			total += int(value)
	summary["total"] = total
	return summary


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}
