extends Node

signal actor_turn_started(actor: Node, actor_id: String, group_id: String, side: String, current_ap: float)
signal actor_turn_ended(actor: Node, actor_id: String, group_id: String, side: String, remaining_ap: float)
signal group_turn_started(group_id: String, order: int)
signal ap_changed(actor: Node, actor_id: String, old_ap: float, new_ap: float)
signal combat_state_changed(in_combat: bool)
signal action_rejected(actor: Node, action_type: String, reason: String)

const ACTION_PHASE_START: String = "start"
const ACTION_PHASE_STEP: String = "step"
const ACTION_PHASE_COMPLETE: String = "complete"

const ACTION_TYPE_MOVE: String = "move"
const ACTION_TYPE_ATTACK: String = "attack"
const ACTION_TYPE_INTERACT: String = "interact"
const ACTION_TYPE_ITEM: String = "item"
const ACTION_TYPE_DEFEND: String = "defend"
const ACTION_TYPE_FLEE: String = "flee"

const TURN_AP_GAIN: float = 1.0
const TURN_AP_MAX: float = 1.5
const ACTION_COST: float = 1.0
const AFFORDABLE_THRESHOLD: float = 1.0

const DEFAULT_GROUP_ORDERS: Dictionary = {
	"player": 0,
	"friendly": 10
}

const ACTION_CONCURRENCY_LIMITS: Dictionary = {
	ACTION_TYPE_ATTACK: 1
}

var _actor_states: Dictionary = {}
var _actor_keys_by_instance: Dictionary = {}
var _group_orders: Dictionary = DEFAULT_GROUP_ORDERS.duplicate(true)
var _registration_counter: int = 0

var _active_action_counts: Dictionary = {}
var _active_actor_actions: Dictionary = {}

var _combat_active: bool = false
var _combat_turn_counter: int = 0
var _current_group_id: String = ""
var _current_actor_key: String = ""

var _world_cycle_running: bool = false
var _pending_world_cycles: int = 0

func _ready() -> void:
	register_group("player", int(DEFAULT_GROUP_ORDERS.get("player", 0)))
	register_group("friendly", int(DEFAULT_GROUP_ORDERS.get("friendly", 10)))

func register_group(group_id: String, order: int) -> void:
	var resolved_group_id: String = group_id.strip_edges()
	if resolved_group_id.is_empty():
		return
	_group_orders[resolved_group_id] = order

func register_actor(actor: Node, group_id: String, side: String) -> void:
	if actor == null or not is_instance_valid(actor):
		return

	var instance_id: int = actor.get_instance_id()
	var state_key: String = str(_actor_keys_by_instance.get(instance_id, ""))
	var actor_id: String = _resolve_actor_id(actor)
	var registration_index: int = _registration_counter
	if state_key.is_empty():
		state_key = str(instance_id)
		_registration_counter += 1
	else:
		var previous_state: Dictionary = _actor_states.get(state_key, {})
		registration_index = int(previous_state.get("registration_index", 0))

	var resolved_group_id: String = group_id.strip_edges()
	if resolved_group_id.is_empty():
		resolved_group_id = "friendly"
	register_group(resolved_group_id, int(_group_orders.get(resolved_group_id, 100 + registration_index)))

	var previous_ap: float = 0.0
	if _actor_states.has(state_key):
		previous_ap = float((_actor_states[state_key] as Dictionary).get("ap", 0.0))

	var state: Dictionary = {
		"key": state_key,
		"actor": actor,
		"actor_id": actor_id,
		"group_id": resolved_group_id,
		"side": side.strip_edges(),
		"ap": clampf(previous_ap, 0.0, TURN_AP_MAX),
		"registration_index": registration_index,
		"turn_open": false,
		"in_combat": _combat_active
	}
	_actor_states[state_key] = state
	_actor_keys_by_instance[instance_id] = state_key
	_cleanup_invalid_current_turn()

func unregister_actor(actor: Node) -> void:
	var state: Dictionary = _get_actor_state(actor)
	if state.is_empty():
		return

	_release_action_slot_if_needed(str(state.get("key", "")))
	var key: String = str(state.get("key", ""))
	_actor_states.erase(key)
	_actor_keys_by_instance.erase(actor.get_instance_id())

	if key == _current_actor_key:
		_current_actor_key = ""
	if str(state.get("group_id", "")) == _current_group_id and _get_group_actor_keys(_current_group_id).is_empty():
		_current_group_id = ""

	call_deferred("exit_combat_if_resolved")

func can_actor_afford(actor: Node, action_type: String, payload: Dictionary = {}) -> bool:
	var state: Dictionary = _get_actor_state(actor)
	if state.is_empty():
		return false
	return float(state.get("ap", 0.0)) >= _resolve_action_cost(action_type, payload)

func request_action(actor: Node, action_type: String, payload: Dictionary = {}) -> Dictionary:
	var state: Dictionary = _get_actor_state(actor)
	if state.is_empty():
		return _build_action_result(false, "unknown_actor", 0.0, 0.0, 0.0, false)

	var phase: String = str(payload.get("phase", ACTION_PHASE_START))
	match phase:
		ACTION_PHASE_STEP:
			return _request_action_step(state, action_type, payload)
		ACTION_PHASE_COMPLETE:
			return _request_action_complete(state, action_type, payload)
		_:
			return _request_action_start(state, action_type, payload)

func enter_combat(trigger_actor: Node, target_actor: Node) -> void:
	var trigger_state: Dictionary = _get_actor_state(trigger_actor)
	if trigger_state.is_empty():
		return

	_cleanup_invalid_current_turn()
	if not _combat_active:
		_combat_active = true
		for key_variant in _actor_states.keys():
			var state: Dictionary = _actor_states[key_variant]
			state["in_combat"] = true
			_actor_states[key_variant] = state
		combat_state_changed.emit(true)

	_current_actor_key = str(trigger_state.get("key", ""))
	_current_group_id = str(trigger_state.get("group_id", ""))
	if not bool(trigger_state.get("turn_open", false)):
		_start_actor_turn(_current_actor_key)
	else:
		_emit_group_turn_started(_current_group_id)

	if target_actor != null and is_instance_valid(target_actor):
		var target_state: Dictionary = _get_actor_state(target_actor)
		if not target_state.is_empty():
			target_state["in_combat"] = true
			_actor_states[str(target_state.get("key", ""))] = target_state

func exit_combat_if_resolved() -> void:
	if not _combat_active:
		return

	var friendly_count: int = 0
	var hostile_count: int = 0
	for state_variant in _actor_states.values():
		var state: Dictionary = state_variant
		var actor: Node = state.get("actor", null) as Node
		if actor == null or not is_instance_valid(actor):
			continue
		var side: String = str(state.get("side", ""))
		if side == "hostile":
			hostile_count += 1
		elif side == "player" or side == "friendly":
			friendly_count += 1

	if hostile_count > 0 and friendly_count > 0:
		return

	_finish_combat_state()

func force_end_combat() -> void:
	if not _combat_active:
		return
	_finish_combat_state()

func is_in_combat() -> bool:
	return _combat_active

func get_current_actor() -> Node:
	var state: Dictionary = _actor_states.get(_current_actor_key, {})
	return state.get("actor", null) as Node

func get_current_group_id() -> String:
	return _current_group_id

func get_current_turn_index() -> int:
	return _combat_turn_counter

func is_actor_current_turn(actor: Node) -> bool:
	var state: Dictionary = _get_actor_state(actor)
	if state.is_empty():
		return false
	return _combat_active and str(state.get("key", "")) == _current_actor_key

func is_player_input_allowed(actor: Node) -> bool:
	if not _combat_active:
		return true
	return is_actor_current_turn(actor)

func get_actor_ap(actor: Node) -> float:
	var state: Dictionary = _get_actor_state(actor)
	if state.is_empty():
		return 0.0
	return float(state.get("ap", 0.0))

func set_actor_ap(actor: Node, ap_value: float) -> void:
	var state: Dictionary = _get_actor_state(actor)
	if state.is_empty():
		return
	var key: String = str(state.get("key", ""))
	var old_ap: float = float(state.get("ap", 0.0))
	state["ap"] = clampf(ap_value, 0.0, TURN_AP_MAX)
	_actor_states[key] = state
	var actor_node: Node = state.get("actor", null) as Node
	if actor_node != null and is_instance_valid(actor_node):
		ap_changed.emit(actor_node, str(state.get("actor_id", "")), old_ap, float(state.get("ap", 0.0)))

func get_actor_available_steps(actor: Node) -> int:
	return int(floor(get_actor_ap(actor) / ACTION_COST))

func get_actor_side(actor: Node) -> String:
	var state: Dictionary = _get_actor_state(actor)
	if state.is_empty():
		return ""
	return str(state.get("side", ""))

func get_actor_group_id(actor: Node) -> String:
	var state: Dictionary = _get_actor_state(actor)
	if state.is_empty():
		return ""
	return str(state.get("group_id", ""))

func reset_runtime_state() -> void:
	_actor_states.clear()
	_actor_keys_by_instance.clear()
	_active_action_counts.clear()
	_active_actor_actions.clear()
	_group_orders = DEFAULT_GROUP_ORDERS.duplicate(true)
	_registration_counter = 0
	_current_group_id = ""
	_current_actor_key = ""
	_world_cycle_running = false
	_pending_world_cycles = 0
	_combat_active = false
	_combat_turn_counter = 0
	register_group("player", int(DEFAULT_GROUP_ORDERS.get("player", 0)))
	register_group("friendly", int(DEFAULT_GROUP_ORDERS.get("friendly", 10)))

func _request_action_start(state: Dictionary, action_type: String, payload: Dictionary) -> Dictionary:
	var actor: Node = state.get("actor", null) as Node
	var key: String = str(state.get("key", ""))
	var old_ap: float = float(state.get("ap", 0.0))
	if not _validate_turn_access(state):
		return _reject_action(actor, action_type, "not_actor_turn", old_ap, old_ap)

	if not bool(state.get("turn_open", false)):
		_start_actor_turn(key)
		state = _actor_states.get(key, {})
		old_ap = float(state.get("ap", 0.0))

	var action_cost: float = _resolve_action_cost(action_type, payload)
	if old_ap < action_cost:
		return _reject_action(actor, action_type, "insufficient_ap", old_ap, old_ap)
	if _is_action_limit_reached(action_type):
		return _reject_action(actor, action_type, "action_limit_reached", old_ap, old_ap)
	if _active_actor_actions.has(key):
		return _reject_action(actor, action_type, "action_in_progress", old_ap, old_ap)

	_claim_action_slot(key, action_type)
	var entered_combat: bool = false
	if _should_enter_combat(action_type, payload):
		var target_actor: Node = payload.get("target_actor", null) as Node
		enter_combat(actor, target_actor)
		entered_combat = _combat_active
		state = _actor_states.get(key, {})
		old_ap = float(state.get("ap", 0.0))

	return _build_action_result(true, "", old_ap, old_ap, 0.0, entered_combat)

func _request_action_step(state: Dictionary, action_type: String, payload: Dictionary) -> Dictionary:
	var actor: Node = state.get("actor", null) as Node
	var key: String = str(state.get("key", ""))
	if not _active_actor_actions.has(key):
		return _reject_action(actor, action_type, "action_not_started", float(state.get("ap", 0.0)), float(state.get("ap", 0.0)))

	var action_state: Dictionary = _active_actor_actions[key]
	if str(action_state.get("type", "")) != action_type:
		return _reject_action(actor, action_type, "action_type_mismatch", float(state.get("ap", 0.0)), float(state.get("ap", 0.0)))

	var cost: float = _resolve_action_cost(action_type, payload)
	var old_ap: float = float(state.get("ap", 0.0))
	if old_ap < cost:
		return _reject_action(actor, action_type, "insufficient_ap", old_ap, old_ap)

	var new_ap: float = clampf(old_ap - cost, 0.0, TURN_AP_MAX)
	state["ap"] = new_ap
	_actor_states[key] = state
	action_state["consumed"] = float(action_state.get("consumed", 0.0)) + cost
	_active_actor_actions[key] = action_state
	ap_changed.emit(actor, str(state.get("actor_id", "")), old_ap, new_ap)
	return _build_action_result(true, "", old_ap, new_ap, cost, _combat_active)

func _request_action_complete(state: Dictionary, action_type: String, payload: Dictionary) -> Dictionary:
	var actor: Node = state.get("actor", null) as Node
	var key: String = str(state.get("key", ""))
	if not _active_actor_actions.has(key):
		return _reject_action(actor, action_type, "action_not_started", float(state.get("ap", 0.0)), float(state.get("ap", 0.0)))

	var action_state: Dictionary = _active_actor_actions[key]
	if str(action_state.get("type", "")) != action_type:
		return _reject_action(actor, action_type, "action_type_mismatch", float(state.get("ap", 0.0)), float(state.get("ap", 0.0)))

	var old_ap: float = float(state.get("ap", 0.0))
	var total_consumed: float = float(action_state.get("consumed", 0.0))
	var complete_cost: float = 0.0
	if action_type != ACTION_TYPE_MOVE and bool(payload.get("success", true)):
		complete_cost = maxf(0.0, _resolve_action_cost(action_type, payload) - total_consumed)
		if complete_cost > 0.0:
			if old_ap < complete_cost:
				_release_action_slot_if_needed(key)
				return _reject_action(actor, action_type, "insufficient_ap", old_ap, old_ap)
			var new_ap: float = clampf(old_ap - complete_cost, 0.0, TURN_AP_MAX)
			state["ap"] = new_ap
			_actor_states[key] = state
			ap_changed.emit(actor, str(state.get("actor_id", "")), old_ap, new_ap)
			old_ap = new_ap
			total_consumed += complete_cost

	_release_action_slot_if_needed(key)

	if _combat_active:
		if str(state.get("key", "")) == _current_actor_key and bool(payload.get("success", true)):
			_end_current_combat_turn()
	else:
		if str(state.get("side", "")) == "player" and bool(payload.get("success", true)):
			_schedule_world_cycle()

	return _build_action_result(
		true,
		"",
		float(action_state.get("ap_before", old_ap)),
		float(state.get("ap", old_ap)),
		total_consumed,
		bool(payload.get("entered_combat", false))
	)

func _validate_turn_access(state: Dictionary) -> bool:
	var actor: Node = state.get("actor", null) as Node
	if actor == null or not is_instance_valid(actor):
		return false
	if not _combat_active:
		return true
	return str(state.get("key", "")) == _current_actor_key

func _should_enter_combat(action_type: String, payload: Dictionary) -> bool:
	if action_type != ACTION_TYPE_ATTACK:
		return false
	if _combat_active:
		return false
	return payload.get("target_actor", null) != null

func _claim_action_slot(actor_key: String, action_type: String) -> void:
	var state: Dictionary = _actor_states.get(actor_key, {})
	_active_actor_actions[actor_key] = {
		"type": action_type,
		"consumed": 0.0,
		"ap_before": float(state.get("ap", 0.0))
	}
	if ACTION_CONCURRENCY_LIMITS.has(action_type):
		_active_action_counts[action_type] = int(_active_action_counts.get(action_type, 0)) + 1

func _release_action_slot_if_needed(actor_key: String) -> void:
	if not _active_actor_actions.has(actor_key):
		return
	var action_state: Dictionary = _active_actor_actions[actor_key]
	var action_type: String = str(action_state.get("type", ""))
	_active_actor_actions.erase(actor_key)
	if ACTION_CONCURRENCY_LIMITS.has(action_type):
		_active_action_counts[action_type] = maxi(0, int(_active_action_counts.get(action_type, 0)) - 1)

func _is_action_limit_reached(action_type: String) -> bool:
	if not ACTION_CONCURRENCY_LIMITS.has(action_type):
		return false
	return int(_active_action_counts.get(action_type, 0)) >= int(ACTION_CONCURRENCY_LIMITS[action_type])

func _schedule_world_cycle() -> void:
	if _combat_active:
		return
	if _world_cycle_running:
		_pending_world_cycles += 1
		return
	call_deferred("_run_world_cycle")

func _run_world_cycle() -> void:
	if _world_cycle_running or _combat_active:
		return
	_world_cycle_running = true
	await _run_world_cycle_async()
	_world_cycle_running = false
	_reset_noncombat_turns()
	if _pending_world_cycles > 0:
		_pending_world_cycles = 0
		call_deferred("_run_world_cycle")

func _run_world_cycle_async() -> void:
	for group_id in _get_sorted_group_ids():
		if group_id == "player":
			continue
		_emit_group_turn_started(group_id)
		for actor_key in _get_group_actor_keys(group_id):
			if _combat_active:
				return
			await _run_actor_turn(actor_key)

func _run_actor_turn(actor_key: String) -> void:
	var state: Dictionary = _actor_states.get(actor_key, {})
	if state.is_empty():
		return
	var actor: Node = state.get("actor", null) as Node
	if actor == null or not is_instance_valid(actor):
		return
	_start_actor_turn(actor_key)
	while float((_actor_states.get(actor_key, {}) as Dictionary).get("ap", 0.0)) >= AFFORDABLE_THRESHOLD:
		var performed: bool = await _execute_actor_turn_step(actor_key)
		if not performed:
			break
	_end_actor_turn(actor_key)

func _execute_actor_turn_step(actor_key: String) -> bool:
	var state: Dictionary = _actor_states.get(actor_key, {})
	if state.is_empty():
		return false
	var actor: Node = state.get("actor", null) as Node
	if actor == null or not is_instance_valid(actor):
		return false
	var ai_controller: Node = actor.get_node_or_null("AIController")
	if ai_controller == null or not ai_controller.has_method("execute_turn_step"):
		return false
	var result: Variant = ai_controller.call("execute_turn_step")
	var result_object: Object = result as Object
	if result_object != null and result_object.get_class() == "GDScriptFunctionState":
		result = await result
	if result is Dictionary:
		return bool((result as Dictionary).get("performed", false))
	return bool(result)

func _start_actor_turn(actor_key: String) -> void:
	var state: Dictionary = _actor_states.get(actor_key, {})
	if state.is_empty():
		return
	var actor: Node = state.get("actor", null) as Node
	if actor == null or not is_instance_valid(actor):
		return
	var group_id: String = str(state.get("group_id", ""))
	_emit_group_turn_started(group_id)
	var old_ap: float = float(state.get("ap", 0.0))
	var new_ap: float = clampf(old_ap + TURN_AP_GAIN, 0.0, TURN_AP_MAX)
	state["ap"] = new_ap
	state["turn_open"] = true
	_actor_states[actor_key] = state
	ap_changed.emit(actor, str(state.get("actor_id", "")), old_ap, new_ap)
	actor_turn_started.emit(actor, str(state.get("actor_id", "")), group_id, str(state.get("side", "")), new_ap)

func _end_actor_turn(actor_key: String) -> void:
	var state: Dictionary = _actor_states.get(actor_key, {})
	if state.is_empty():
		return
	var actor: Node = state.get("actor", null) as Node
	if actor == null or not is_instance_valid(actor):
		return
	state["turn_open"] = false
	_actor_states[actor_key] = state
	actor_turn_ended.emit(actor, str(state.get("actor_id", "")), str(state.get("group_id", "")), str(state.get("side", "")), float(state.get("ap", 0.0)))

func _end_current_combat_turn() -> void:
	if _current_actor_key.is_empty():
		return
	_end_actor_turn(_current_actor_key)
	exit_combat_if_resolved()
	if not _combat_active:
		return
	_select_next_combat_actor()

func _select_next_combat_actor() -> void:
	var ordered_groups: Array[String] = _get_sorted_group_ids()
	if ordered_groups.is_empty():
		return

	var group_index: int = maxi(ordered_groups.find(_current_group_id), 0)
	var actor_key: String = _current_actor_key
	var next_selection: Dictionary = _find_next_combat_actor(ordered_groups, group_index, actor_key)
	if next_selection.is_empty():
		return

	_current_group_id = str(next_selection.get("group_id", ""))
	_current_actor_key = str(next_selection.get("actor_key", ""))
	_combat_turn_counter += 1
	_start_actor_turn(_current_actor_key)

	var actor_state: Dictionary = _actor_states.get(_current_actor_key, {})
	if actor_state.is_empty():
		return
	var actor: Node = actor_state.get("actor", null) as Node
	if actor != null and is_instance_valid(actor) and not actor.is_in_group("player"):
		call_deferred("_run_combat_ai_turn", _current_actor_key)

func _run_combat_ai_turn(actor_key: String) -> void:
	if not _combat_active or actor_key != _current_actor_key:
		return
	while _combat_active and actor_key == _current_actor_key:
		var state: Dictionary = _actor_states.get(actor_key, {})
		if state.is_empty():
			return
		if float(state.get("ap", 0.0)) < AFFORDABLE_THRESHOLD:
			break
		var performed: bool = await _execute_actor_turn_step(actor_key)
		if not performed:
			break
	if _combat_active and actor_key == _current_actor_key:
		_end_current_combat_turn()

func _find_next_combat_actor(ordered_groups: Array[String], start_group_index: int, actor_key: String) -> Dictionary:
	if ordered_groups.is_empty():
		return {}

	var visited: int = 0
	var group_index: int = start_group_index
	var search_after_actor: String = actor_key
	while visited < ordered_groups.size():
		var group_id: String = ordered_groups[group_index]
		var actor_keys: Array[String] = _get_group_actor_keys(group_id)
		if not actor_keys.is_empty():
			var actor_index: int = actor_keys.find(search_after_actor)
			if actor_index < -1:
				actor_index = -1
			for next_index in range(actor_index + 1, actor_keys.size()):
				return {
					"group_id": group_id,
					"actor_key": actor_keys[next_index]
				}
			for next_index in range(0, actor_index + 1):
				if next_index < actor_keys.size():
					return {
						"group_id": group_id,
						"actor_key": actor_keys[next_index]
					}
		visited += 1
		group_index = (group_index + 1) % ordered_groups.size()
		search_after_actor = ""
	return {}

func _get_sorted_group_ids() -> Array[String]:
	var group_ids: Array[String] = []
	for group_variant in _group_orders.keys():
		group_ids.append(str(group_variant))
	group_ids.sort_custom(func(a: String, b: String) -> bool:
		var order_a: int = int(_group_orders.get(a, 9999))
		var order_b: int = int(_group_orders.get(b, 9999))
		if order_a == order_b:
			return a < b
		return order_a < order_b
	)
	return group_ids

func _get_group_actor_keys(group_id: String) -> Array[String]:
	var actor_keys: Array[String] = []
	for key_variant in _actor_states.keys():
		var state: Dictionary = _actor_states[key_variant]
		var actor: Node = state.get("actor", null) as Node
		if actor == null or not is_instance_valid(actor):
			continue
		if str(state.get("group_id", "")) != group_id:
			continue
		actor_keys.append(str(key_variant))
	actor_keys.sort_custom(func(a: String, b: String) -> bool:
		var state_a: Dictionary = _actor_states.get(a, {})
		var state_b: Dictionary = _actor_states.get(b, {})
		return int(state_a.get("registration_index", 0)) < int(state_b.get("registration_index", 0))
	)
	return actor_keys

func _reset_noncombat_turns() -> void:
	for key_variant in _actor_states.keys():
		var state: Dictionary = _actor_states[key_variant]
		state["turn_open"] = false
		_actor_states[key_variant] = state

func _cleanup_invalid_current_turn() -> void:
	if _current_actor_key.is_empty():
		return
	var state: Dictionary = _actor_states.get(_current_actor_key, {})
	if state.is_empty():
		_current_actor_key = ""
		return
	var actor: Node = state.get("actor", null) as Node
	if actor == null or not is_instance_valid(actor):
		_current_actor_key = ""

func _resolve_action_cost(action_type: String, payload: Dictionary) -> float:
	if action_type == ACTION_TYPE_MOVE and payload.has("steps"):
		return float(payload.get("steps", 1)) * ACTION_COST
	return ACTION_COST

func _resolve_actor_id(actor: Node) -> String:
	if actor == null:
		return ""
	if actor.has_meta("character_id"):
		var character_id: String = str(actor.get_meta("character_id"))
		if not character_id.is_empty():
			return character_id
	if actor.is_in_group("player"):
		return "player"
	return str(actor.name)

func _get_actor_state(actor: Node) -> Dictionary:
	if actor == null or not is_instance_valid(actor):
		return {}
	var instance_id: int = actor.get_instance_id()
	if not _actor_keys_by_instance.has(instance_id):
		return {}
	var key: String = str(_actor_keys_by_instance[instance_id])
	return _actor_states.get(key, {})

func _build_action_result(success: bool, reason: String, ap_before: float, ap_after: float, consumed: float, entered_combat: bool) -> Dictionary:
	return {
		"success": success,
		"reason": reason,
		"ap_before": ap_before,
		"ap_after": ap_after,
		"consumed": consumed,
		"entered_combat": entered_combat
	}

func _reject_action(actor: Node, action_type: String, reason: String, ap_before: float, ap_after: float) -> Dictionary:
	action_rejected.emit(actor, action_type, reason)
	return _build_action_result(false, reason, ap_before, ap_after, 0.0, _combat_active)

func _emit_group_turn_started(group_id: String) -> void:
	if group_id.is_empty():
		return
	group_turn_started.emit(group_id, int(_group_orders.get(group_id, 0)))

func _finish_combat_state() -> void:
	_combat_active = false
	_current_actor_key = ""
	_current_group_id = ""
	_combat_turn_counter = 0
	for key_variant in _actor_states.keys():
		var state: Dictionary = _actor_states[key_variant]
		state["in_combat"] = false
		state["turn_open"] = false
		_actor_states[key_variant] = state
	combat_state_changed.emit(false)
