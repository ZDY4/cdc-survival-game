extends RefCounted

const WorldSnapshotBuilder = preload("res://scripts/world/world_snapshot_builder.gd")

var registry: RefCounted
var last_refresh_report: Dictionary = {}


func _init(p_registry: RefCounted = null) -> void:
	registry = p_registry


func configure(p_registry: RefCounted) -> void:
	registry = p_registry


func rebuild_world_result(simulation: RefCounted, interaction_controller: RefCounted = null, source: String = "") -> Dictionary:
	if registry == null:
		return {"ok": false, "reason": "registry_missing", "source": source, "world_result": {}}
	if simulation == null:
		return {"ok": false, "reason": "simulation_missing", "source": source, "world_result": {}}
	var runtime_snapshot: Dictionary = simulation.snapshot()
	var built: Dictionary = build_world_result_from_snapshot(runtime_snapshot, source)
	var next_world_result: Dictionary = _dictionary_or_empty(built.get("world_result", {}))
	var applied: Dictionary = apply_existing_world_result(simulation, interaction_controller, next_world_result, source)
	applied["runtime_context"] = _runtime_log_context(runtime_snapshot)
	return applied


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
		"runtime_context": _runtime_log_context(runtime_snapshot),
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
	var output := {
		"ok": true,
		"source": source,
		"world_result": next_world_result,
		"map": _dictionary_or_empty(next_world_result.get("map", {})),
	}
	if simulation != null:
		output["runtime_context"] = _runtime_log_context(simulation.snapshot())
	return output


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
	refresh["command_kind"] = str(pending_refresh.get("command_kind", ""))
	refresh["presenter_kind"] = str(pending_refresh.get("presenter_kind", ""))
	refresh["queued_sequence"] = int(pending_refresh.get("queued_sequence", 0))
	refresh["refresh_after"] = str(pending_refresh.get("refresh_after", ""))
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
	_record_refresh_report(accepted)
	if not bool(accepted.get("ok", false)):
		push_error(refresh_failure_message(accepted, fallback_error))
	return accepted


func refresh_report_snapshot() -> Dictionary:
	return last_refresh_report.duplicate(true)


func refresh_failure_message(accepted: Dictionary, fallback_error: String = "world refresh failed") -> String:
	var context: Dictionary = _dictionary_or_empty(accepted.get("log_context", {}))
	var parts: Array[String] = []
	for key in ["source", "reason", "command_kind", "map_id", "actor_id"]:
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
	var runtime_context: Dictionary = _dictionary_or_empty(refresh.get("runtime_context", {}))
	var player: Dictionary = _player_log_context(world)
	return {
		"source": str(refresh.get("source", "")),
		"reason": str(refresh.get("reason", "")),
		"command_kind": str(refresh.get("command_kind", "")),
		"presenter_kind": str(refresh.get("presenter_kind", "")),
		"queued_sequence": int(refresh.get("queued_sequence", 0)),
		"refresh_after": str(refresh.get("refresh_after", "")),
		"map_id": str(map.get("id", map.get("map_id", ""))),
		"active_map_id": str(runtime_context.get("active_map_id", "")),
		"active_location_id": str(runtime_context.get("active_location_id", "")),
		"actor_id": str(player.get("actor_id", player.get("id", ""))),
		"actor_definition_id": str(player.get("definition_id", "")),
		"actor_count": _array_or_empty(world.get("actors", [])).size(),
		"corpse_count": _array_or_empty(world.get("corpses", [])).size(),
		"map_object_count": int(map.get("object_count", _array_or_empty(map.get("objects", [])).size())),
		"interaction_target_count": _dictionary_or_empty(map.get("interaction_targets", {})).size(),
		"container_session_count": int(runtime_context.get("container_session_count", 0)),
		"shop_session_count": int(runtime_context.get("shop_session_count", 0)),
		"world_day": int(runtime_context.get("world_day", 0)),
		"world_minute": int(runtime_context.get("world_minute", 0)),
	}


func _record_refresh_report(accepted: Dictionary) -> void:
	var context: Dictionary = _dictionary_or_empty(accepted.get("log_context", {}))
	last_refresh_report = {
		"ok": bool(accepted.get("ok", false)),
		"source": str(accepted.get("source", context.get("source", ""))),
		"reason": str(accepted.get("reason", context.get("reason", ""))),
		"command_kind": str(context.get("command_kind", "")),
		"presenter_kind": str(context.get("presenter_kind", "")),
		"queued_sequence": int(context.get("queued_sequence", 0)),
		"refresh_after": str(context.get("refresh_after", "")),
		"map_id": str(context.get("map_id", "")),
		"active_map_id": str(context.get("active_map_id", "")),
		"active_location_id": str(context.get("active_location_id", "")),
		"actor_id": str(context.get("actor_id", "")),
		"actor_definition_id": str(context.get("actor_definition_id", "")),
		"actor_count": int(context.get("actor_count", 0)),
		"corpse_count": int(context.get("corpse_count", 0)),
		"map_object_count": int(context.get("map_object_count", 0)),
		"interaction_target_count": int(context.get("interaction_target_count", 0)),
		"container_session_count": int(context.get("container_session_count", 0)),
		"shop_session_count": int(context.get("shop_session_count", 0)),
		"world_day": int(context.get("world_day", 0)),
		"world_minute": int(context.get("world_minute", 0)),
		"error_message": str(accepted.get("error_message", "")),
	}


func _runtime_log_context(runtime_snapshot: Dictionary) -> Dictionary:
	var world_time: Dictionary = _dictionary_or_empty(runtime_snapshot.get("world_time", {}))
	return {
		"active_map_id": str(runtime_snapshot.get("active_map_id", "")),
		"active_location_id": str(runtime_snapshot.get("active_location_id", "")),
		"actor_count": _array_or_empty(runtime_snapshot.get("actors", [])).size(),
		"container_session_count": _array_or_empty(runtime_snapshot.get("container_sessions", [])).size(),
		"shop_session_count": _array_or_empty(runtime_snapshot.get("shop_sessions", [])).size(),
		"world_day": int(world_time.get("day", runtime_snapshot.get("world_day", 0))),
		"world_minute": int(world_time.get("minute", runtime_snapshot.get("world_minute", 0))),
	}


func _player_log_context(world_result: Dictionary) -> Dictionary:
	var fallback: Dictionary = {}
	for value in _array_or_empty(world_result.get("actors", [])):
		var actor: Dictionary = _dictionary_or_empty(value)
		if fallback.is_empty() and int(actor.get("actor_id", 0)) == 1:
			fallback = actor
		if str(actor.get("kind", "")) == "player":
			return actor
	return fallback


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
