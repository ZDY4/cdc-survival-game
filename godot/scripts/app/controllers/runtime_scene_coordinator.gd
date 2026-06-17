extends RefCounted

const WorldRoot = preload("res://scripts/world/world_root.gd")
const WorldRootScene = preload("res://scenes/world/world_root.tscn")
const GameRuntimeInputController = preload("res://scripts/app/controllers/game_runtime_input_controller.gd")

var host


func configure(p_host) -> void:
	host = p_host


func rebuild_world_after_runtime_change(selected_prompt: Dictionary = {}, command_result: Dictionary = {}) -> void:
	if not rebuild_runtime_world_result("runtime_change"):
		return
	apply_runtime_scene_refresh(true, selected_prompt, {
		"present_world_action": true,
		"command_result": command_result,
		"refresh_kind": "all",
	})


func rebuild_runtime_world_result(source: String) -> bool:
	var refresh: Dictionary = dictionary_or_empty(host.runtime_refresh_controller.call("rebuild_world_result", host.simulation, host.interaction_controller, source))
	return accept_runtime_refresh_result(refresh, "world rebuild failed")


func apply_existing_runtime_world_result(next_world_result: Dictionary, source: String, fallback_error: String = "world refresh failed") -> bool:
	var refresh: Dictionary = dictionary_or_empty(host.runtime_refresh_controller.call("apply_existing_world_result", host.simulation, host.interaction_controller, next_world_result, source))
	return accept_runtime_refresh_result(refresh, fallback_error)


func accept_runtime_refresh_result(refresh: Dictionary, fallback_error: String) -> bool:
	var accepted: Dictionary = dictionary_or_empty(host.runtime_refresh_controller.call("accept_and_report_refresh_result", refresh, fallback_error))
	host.world_result = dictionary_or_empty(accepted.get("world_result", {}))
	if not bool(accepted.get("ok", false)):
		return false
	if bool(accepted.get("sync_observed_level", false)):
		host.runtime_view_state_controller.call("sync_observed_level_to_map", host.world_result)
	return true


func world_container_node() -> Node3D:
	if host.world_root != null and host.world_root.has_method("world_container_node"):
		var container := host.world_root.call("world_container_node") as Node3D
		if container != null:
			host._world_container_ref = container
	return host._world_container_ref


func player_actor_id() -> int:
	if host.simulation != null and host.simulation.has_method("_player_actor_id"):
		return int(host.simulation.call("_player_actor_id"))
	return 1


func setup_world_container() -> void:
	if host.world_root == null or not is_instance_valid(host.world_root):
		host.world_root = WorldRootScene.instantiate() as Node3D
		if host.world_root == null:
			host.world_root = WorldRoot.new()
		host.world_root.name = "WorldRoot"
		host.add_child(host.world_root)
	if host.world_root.has_method("ensure_world_container"):
		host._world_container_ref = host.world_root.call("ensure_world_container")


func setup_runtime_input_controller() -> void:
	if host.runtime_input_controller == null:
		host.runtime_input_controller = GameRuntimeInputController.new(host)
	host.runtime_input_controller.attach_world(world_container_node(), host.world_result)
	configure_turn_action_runner()


func configure_turn_action_runner() -> void:
	if host.actor_view_controller != null and host.actor_view_controller.has_method("attach"):
		host.actor_view_controller.call("attach", world_container_node())
	if host.turn_action_runner != null and host.turn_action_runner.has_method("configure"):
		host.turn_action_runner.call("configure", host.simulation, host.actor_view_controller, host, host.world_result)


func refresh_world_runtime_bindings() -> void:
	setup_runtime_input_controller()
	host.call("_configure_runtime_audio_layers")
	host.call("_setup_panels")


func refresh_world_visuals(render_world: bool = true) -> Dictionary:
	var boundary: Dictionary = prepare_structural_refresh_boundary("refresh_world_visuals", render_world)
	var counts: Dictionary = apply_world_root_snapshot(render_world)
	if render_world:
		record_structural_refresh_boundary(boundary, "refresh_world_visuals", counts)
	return counts


func apply_runtime_scene_refresh(render_world: bool = true, selected_prompt: Dictionary = {}, options: Dictionary = {}) -> Dictionary:
	var plan: Dictionary = dictionary_or_empty(host.runtime_refresh_controller.call("build_scene_apply_plan", render_world, selected_prompt, options))
	var should_render := bool(plan.get("render_world", true))
	var source := str(options.get("source", "runtime_scene_refresh"))
	var boundary: Dictionary = prepare_structural_refresh_boundary(source, should_render)
	var counts: Dictionary = apply_world_root_snapshot(should_render)
	if should_render:
		record_structural_refresh_boundary(boundary, source, counts)
	if bool(plan.get("present_world_action", false)):
		host.call("_present_world_action", dictionary_or_empty(plan.get("command_result", {})))
	if bool(plan.get("refresh_runtime_bindings", true)):
		refresh_world_runtime_bindings()
	var refresh_kind := str(plan.get("refresh_kind", "none"))
	var prompt: Dictionary = dictionary_or_empty(plan.get("prompt", {}))
	if refresh_kind == "all":
		host.refresh_all_panels(prompt)
	elif refresh_kind == "hud":
		host.refresh_hud(prompt)
	return counts


func prepare_structural_refresh_boundary(source: String, render_world: bool = true) -> Dictionary:
	var before_runner: Dictionary = host.turn_action_runner_snapshot()
	var before_policy: Dictionary = host.world_render_policy_snapshot()
	var before_phase := str(before_runner.get("phase", ""))
	var runner_busy := bool(before_runner.get("active", false)) or bool(before_runner.get("presentation_active", false))
	var requires_boundary := render_world and runner_busy and before_phase != "finished"
	var boundary_result: Dictionary = {}
	if requires_boundary:
		boundary_result = host.settle_turn_action_runner_boundary("structural_refresh:%s" % source)
		host.refresh_hud(host.current_interaction_prompt())
	return {
		"source": source,
		"render_world": render_world,
		"required": requires_boundary,
		"settled": not requires_boundary or bool(boundary_result.get("settled", false)),
		"boundary_result": boundary_result.duplicate(true),
		"before_runner": before_runner.duplicate(true),
		"after_runner": host.turn_action_runner_snapshot(),
		"before_policy": before_policy.duplicate(true),
		"after_policy": host.world_render_policy_snapshot(),
	}


func record_structural_refresh_boundary(boundary: Dictionary, source: String, counts: Dictionary) -> void:
	var record: Dictionary = boundary.duplicate(true)
	record["source"] = source
	record["rendered"] = true
	record["render_sequence"] = int(host.runtime_performance_snapshot().get("render_sequence", 0))
	record["counts"] = counts.duplicate(true)
	host.latest_structural_refresh_boundary = record


func apply_world_root_snapshot(render_world: bool = true) -> Dictionary:
	setup_world_container()
	if host.world_root == null:
		return {}
	var runtime_snapshot: Dictionary = host.simulation.snapshot() if host.simulation != null else {}
	var apply_result: Dictionary = dictionary_or_empty(host.world_root.call("apply_runtime_snapshot", host.world_result, runtime_snapshot, host.current_debug_overlay_mode(), render_world))
	var counts: Dictionary = dictionary_or_empty(apply_result.get("counts", {}))
	if render_world:
		host.runtime_performance_tracker.call("record_world_render", counts, host.world_root)
	elif host.runtime_input_controller != null:
		host.runtime_input_controller.world_result = host.world_result
	host._world_container_ref = apply_result.get("world_container", host._world_container_ref) as Node3D
	host._fog_overlay_ref = apply_result.get("fog_overlay", host._fog_overlay_ref) as ColorRect
	return counts


func runtime_refresh_report_snapshot() -> Dictionary:
	if host.runtime_refresh_controller != null and host.runtime_refresh_controller.has_method("refresh_report_snapshot"):
		return dictionary_or_empty(host.runtime_refresh_controller.call("refresh_report_snapshot"))
	return {}


func structural_refresh_boundary_snapshot() -> Dictionary:
	return host.latest_structural_refresh_boundary.duplicate(true)


func dictionary_or_empty(value: Variant) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}
