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


func apply_pending_final_refresh(simulation: RefCounted, interaction_controller: RefCounted, pending_refresh: Dictionary, fallback_error: String = "world refresh failed") -> Dictionary:
	if pending_refresh.is_empty():
		return {
			"ok": false,
			"reason": "pending_refresh_missing",
			"error_message": "pending_refresh_missing",
			"world_result": {},
			"render_world": true,
			"refresh_all_panels": false,
			"prompt": {},
		}
	var resolved: Dictionary = resolve_pending_final_world_result(simulation, pending_refresh)
	var final_world_result: Dictionary = _dictionary_or_empty(resolved.get("world_result", {}))
	var refresh: Dictionary = apply_existing_world_result(simulation, interaction_controller, final_world_result, "world_result_without_present")
	var accepted: Dictionary = accept_and_report_refresh_result(refresh, fallback_error)
	accepted["pending_refresh"] = pending_refresh.duplicate(true)
	accepted["resolved"] = resolved.duplicate(true)
	accepted["render_world"] = bool(pending_refresh.get("render_world", true))
	accepted["refresh_all_panels"] = bool(pending_refresh.get("refresh_all_panels", false))
	accepted["prompt"] = _dictionary_or_empty(pending_refresh.get("prompt", {})).duplicate(true)
	return accepted


func accept_refresh_result(refresh: Dictionary, fallback_error: String = "world refresh failed") -> Dictionary:
	var next_world_result: Dictionary = _dictionary_or_empty(refresh.get("world_result", {}))
	var ok := bool(refresh.get("ok", false))
	return {
		"ok": ok,
		"world_result": next_world_result,
		"source": str(refresh.get("source", "")),
		"reason": str(refresh.get("reason", "")),
		"error_message": "" if ok else refresh_error_message(refresh, fallback_error),
		"log_context": refresh_log_context(refresh, next_world_result),
		"sync_observed_level": ok,
	}


func accept_and_report_refresh_result(refresh: Dictionary, fallback_error: String = "world refresh failed") -> Dictionary:
	var accepted: Dictionary = accept_refresh_result(refresh, fallback_error)
	if not bool(accepted.get("ok", false)):
		push_error(refresh_failure_message(accepted, fallback_error))
	return accepted


func refresh_failure_message(accepted: Dictionary, fallback_error: String = "world refresh failed") -> String:
	var context: Dictionary = _dictionary_or_empty(accepted.get("log_context", {}))
	var parts: Array[String] = []
	for key in ["source", "reason", "map_id", "actor_id"]:
		var value := str(context.get(key, "")).strip_edges()
		if not value.is_empty():
			parts.append("%s=%s" % [key, value])
	var error_message := str(accepted.get("error_message", fallback_error)).strip_edges()
	if parts.is_empty():
		return error_message
	return "%s (%s)" % [error_message, ", ".join(parts)]


func refresh_error_message(refresh: Dictionary, fallback_error: String = "world refresh failed") -> String:
	var error := str(refresh.get("error", "")).strip_edges()
	if not error.is_empty():
		return error
	var reason := str(refresh.get("reason", "")).strip_edges()
	if not reason.is_empty():
		return reason
	return fallback_error


func refresh_log_context(refresh: Dictionary, next_world_result: Dictionary = {}) -> Dictionary:
	var world: Dictionary = next_world_result if not next_world_result.is_empty() else _dictionary_or_empty(refresh.get("world_result", {}))
	var map: Dictionary = _dictionary_or_empty(world.get("map", {}))
	var runtime: Dictionary = _dictionary_or_empty(world.get("runtime", {}))
	var player: Dictionary = _dictionary_or_empty(runtime.get("player", {}))
	return {
		"source": str(refresh.get("source", "")),
		"reason": str(refresh.get("reason", "")),
		"map_id": str(map.get("id", map.get("map_id", ""))),
		"actor_id": str(player.get("actor_id", player.get("id", ""))),
	}


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}
