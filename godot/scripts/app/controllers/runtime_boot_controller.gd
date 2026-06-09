extends RefCounted

const CoreRuntimeBootstrap = preload("res://scripts/core/runtime/runtime_bootstrap.gd")

var registry: RefCounted


func _init(p_registry: RefCounted = null) -> void:
	registry = p_registry


func configure(p_registry: RefCounted) -> void:
	registry = p_registry


func consume_startup_request() -> Dictionary:
	var request: Dictionary = _dictionary_or_empty(ProjectSettings.get_setting("cdc/startup_request", {})).duplicate(true)
	if not request.is_empty():
		ProjectSettings.set_setting("cdc/startup_request", {})
	return request


func build_runtime_from_startup_request(request: Dictionary) -> Dictionary:
	if registry == null:
		return {"ok": false, "reason": "registry_missing", "simulation": null, "snapshot": {}}
	var runtime_result: Dictionary = CoreRuntimeBootstrap.new(registry).build_new_game_runtime()
	var mode := str(request.get("mode", "new_game"))
	if mode != "continue":
		return runtime_result
	var snapshot: Dictionary = _dictionary_or_empty(request.get("runtime_snapshot", {}))
	var loaded_simulation: RefCounted = runtime_result.get("simulation")
	if loaded_simulation == null or snapshot.is_empty():
		push_warning("继续游戏请求缺少有效快照，回退到新游戏")
		return runtime_result
	loaded_simulation.load_snapshot(snapshot)
	return {
		"ok": true,
		"simulation": loaded_simulation,
		"snapshot": loaded_simulation.snapshot(),
	}


func build_startup_runtime() -> Dictionary:
	return build_runtime_from_startup_request(consume_startup_request())


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}
