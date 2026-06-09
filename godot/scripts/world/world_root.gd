extends Node3D

const WorldSceneRenderer = preload("res://scripts/world/world_scene_renderer.gd")
const FogOverlayController = preload("res://scripts/world/fog_overlay_controller.gd")
const DebugOverlayController = preload("res://scripts/world/debug_overlay_controller.gd")

var world_container: Node3D
var fog_overlay: ColorRect
var fog_overlay_controller: RefCounted = FogOverlayController.new()
var debug_overlay_controller: RefCounted = DebugOverlayController.new()
var last_render_counts: Dictionary = {}
var render_sequence: int = 0


func ensure_world_container() -> Node3D:
	if world_container != null and is_instance_valid(world_container):
		return world_container
	world_container = Node3D.new()
	world_container.name = "WorldContainer"
	add_child(world_container)
	return world_container


func apply_world_snapshot(world_snapshot: Dictionary, runtime_snapshot: Dictionary = {}, options: Dictionary = {}) -> Dictionary:
	var container := ensure_world_container()
	var counts: Dictionary = WorldSceneRenderer.new().render_world(container, world_snapshot, options)
	last_render_counts = _render_count_summary(counts)
	render_sequence += 1
	return counts


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
