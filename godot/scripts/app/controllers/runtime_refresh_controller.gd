extends RefCounted

const WorldSnapshotBuilder = preload("res://scripts/world/world_snapshot_builder.gd")

var registry: RefCounted


func _init(p_registry: RefCounted = null) -> void:
	registry = p_registry


func configure(p_registry: RefCounted) -> void:
	registry = p_registry


func rebuild_world_result(simulation: RefCounted, interaction_controller: RefCounted = null, source: String = "") -> Dictionary:
	if registry == null:
		return {"ok": false, "reason": "registry_missing", "source": source, "world_result": {}}
	if simulation == null:
		return {"ok": false, "reason": "simulation_missing", "source": source, "world_result": {}}
	var built: Dictionary = build_world_result_from_snapshot(simulation.snapshot(), source)
	var next_world_result: Dictionary = _dictionary_or_empty(built.get("world_result", {}))
	return apply_existing_world_result(simulation, interaction_controller, next_world_result, source)


func build_world_result_from_snapshot(runtime_snapshot: Dictionary, source: String = "") -> Dictionary:
	if registry == null:
		return {"ok": false, "reason": "registry_missing", "source": source, "world_result": {}}
	var next_world_result: Dictionary = WorldSnapshotBuilder.new(registry).build_from_runtime_snapshot(runtime_snapshot)
	if not bool(next_world_result.get("ok", false)):
		return {
			"ok": false,
			"reason": "world_result_failed",
			"source": source,
			"error": str(next_world_result.get("error", "world refresh failed")),
			"world_result": next_world_result,
		}
	return {
		"ok": true,
		"source": source,
		"world_result": next_world_result,
		"map": _dictionary_or_empty(next_world_result.get("map", {})),
	}


func apply_existing_world_result(simulation: RefCounted, interaction_controller: RefCounted, next_world_result: Dictionary, source: String = "") -> Dictionary:
	if next_world_result.is_empty():
		return {"ok": false, "reason": "world_result_missing", "source": source, "world_result": {}}
	if not bool(next_world_result.get("ok", false)):
		return {
			"ok": false,
			"reason": "world_result_failed",
			"source": source,
			"error": str(next_world_result.get("error", "world refresh failed")),
			"world_result": next_world_result,
		}
	if simulation != null:
		var map: Dictionary = _dictionary_or_empty(next_world_result.get("map", {}))
		simulation.configure_map_interactions(_dictionary_or_empty(map.get("interaction_targets", {})))
	if interaction_controller != null:
		interaction_controller.world_result = next_world_result
	return {
		"ok": true,
		"source": source,
		"world_result": next_world_result,
		"map": _dictionary_or_empty(next_world_result.get("map", {})),
	}


func resolve_pending_final_world_result(simulation: RefCounted, pending_refresh: Dictionary, fallback_source: String = "pending_final_refresh_fallback") -> Dictionary:
	var final_world_result: Dictionary = _dictionary_or_empty(pending_refresh.get("world_result", {}))
	if not final_world_result.is_empty() and bool(final_world_result.get("ok", false)):
		return {
			"ok": true,
			"source": str(pending_refresh.get("source", "")),
			"world_result": final_world_result,
			"used_fallback": false,
		}
	if simulation == null:
		return {
			"ok": false,
			"reason": "simulation_missing",
			"source": fallback_source,
			"world_result": final_world_result,
			"used_fallback": false,
		}
	var fallback_refresh: Dictionary = build_world_result_from_snapshot(simulation.snapshot(), fallback_source)
	return {
		"ok": bool(fallback_refresh.get("ok", false)),
		"reason": str(fallback_refresh.get("reason", "")),
		"error": str(fallback_refresh.get("error", "")),
		"source": fallback_source,
		"world_result": _dictionary_or_empty(fallback_refresh.get("world_result", {})),
		"used_fallback": true,
	}


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}
