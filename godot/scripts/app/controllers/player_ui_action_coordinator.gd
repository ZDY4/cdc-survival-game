extends RefCounted

var host


func configure(p_host) -> void:
	host = p_host


func close_trade_panel(reason: String = "closed") -> void:
	var closed_target: Dictionary = host.active_trade_target.duplicate(true)
	host.active_trade_target = {}
	host.active_trade_feedback = {}
	if not closed_target.is_empty() and host.simulation != null:
		host.simulation.emit_event("trade_closed", trade_closed_payload(closed_target, reason))
	host.refresh_trade_panel()


func choose_dialogue_option(option_ref: Variant) -> Dictionary:
	var dialogue_library: Dictionary = host.registry.get_library("dialogues") if host.registry != null else {}
	var operation: Dictionary = dictionary_or_empty(host.dialogue_action_controller.call("choose_option", host.simulation, option_ref, dialogue_library))
	var result: Dictionary = dictionary_or_empty(operation.get("result", {}))
	apply_dialogue_trade_result(result)
	refresh_dialogue_operation(operation)
	return result


func choose_dialogue_option_by_index(option_index: int) -> Dictionary:
	return choose_dialogue_option(option_index)


func advance_dialogue_without_choice() -> Dictionary:
	var dialogue_snapshot: Dictionary = current_dialogue_snapshot()
	var dialogue_library: Dictionary = host.registry.get_library("dialogues") if host.registry != null else {}
	var operation: Dictionary = dictionary_or_empty(host.dialogue_action_controller.call("continue_without_choice", host.simulation, dialogue_snapshot, dialogue_library))
	var result: Dictionary = dictionary_or_empty(operation.get("result", {}))
	apply_dialogue_trade_result(result)
	refresh_dialogue_operation(operation)
	return result


func refresh_dialogue_operation(operation: Dictionary) -> void:
	host.game_ui_coordinator.call("refresh_operation_panels", array_or_empty(operation.get("refresh", [])))


func apply_dialogue_trade_result(result: Dictionary) -> void:
	if not bool(result.get("success", false)):
		return
	if str(result.get("end_type", "")) == "trade":
		host.active_trade_target = dictionary_or_empty(host.runtime_session_context_controller.call("dialogue_trade_target", result, host.active_trade_target))
		host.active_trade_feedback = {}
	elif bool(result.get("finished", false)) or result.has("end_type"):
		close_trade_panel("dialogue_finished:%s" % str(result.get("end_type", "")))


func has_active_dialogue() -> bool:
	if host.simulation == null:
		return false
	for actor in host.simulation.actor_registry.snapshot():
		var actor_data: Dictionary = dictionary_or_empty(actor)
		if actor_data.get("kind", "") == "player":
			return not str(actor_data.get("active_dialogue_id", "")).is_empty()
	return false


func press_enter_action() -> Dictionary:
	if has_active_dialogue():
		return advance_dialogue_without_choice()
	return {"success": false, "reason": "no_enter_action"}


func take_active_container_item(item_id: String, count: int = 1, stack_index: int = 0) -> Dictionary:
	var operation: Dictionary = dictionary_or_empty(host.container_action_controller.call("take_item", active_container_id(), item_id, count, stack_index, Callable(self, "submit_inventory_action"), Callable(self, "record_container_feedback")))
	return apply_container_action_operation(operation)


func take_active_container_money(count: int = -1) -> Dictionary:
	var operation: Dictionary = dictionary_or_empty(host.container_action_controller.call("take_money", active_container_id(), count, Callable(self, "submit_inventory_action"), Callable(self, "record_container_feedback")))
	return apply_container_action_operation(operation)


func take_all_active_container_items() -> Dictionary:
	var operation: Dictionary = dictionary_or_empty(host.container_action_controller.call("take_all", active_container_id(), Callable(self, "submit_inventory_action"), Callable(self, "record_container_feedback")))
	return apply_container_action_operation(operation)


func store_active_container_item(item_id: String, count: int = 1, stack_index: int = 0) -> Dictionary:
	var operation: Dictionary = dictionary_or_empty(host.container_action_controller.call("store_item", active_container_id(), item_id, count, stack_index, Callable(self, "submit_inventory_action"), Callable(self, "record_container_feedback")))
	return apply_container_action_operation(operation)


func store_all_active_container_items() -> Dictionary:
	var operation: Dictionary = dictionary_or_empty(host.container_action_controller.call("store_all", active_container_id(), Callable(self, "submit_inventory_action"), Callable(self, "record_container_feedback")))
	return apply_container_action_operation(operation)


func transfer_active_container_item(source: String, item_id: String, count: int = 1, stack_index: int = 0) -> Dictionary:
	var operation: Dictionary = dictionary_or_empty(host.container_action_controller.call("transfer_item", source, active_container_id(), item_id, count, stack_index, Callable(self, "submit_inventory_action"), Callable(self, "record_container_feedback")))
	return apply_container_action_operation(operation)


func transfer_all_active_container_items(source: String) -> Dictionary:
	var operation: Dictionary = dictionary_or_empty(host.container_action_controller.call("transfer_all", source, active_container_id(), Callable(self, "submit_inventory_action"), Callable(self, "record_container_feedback")))
	return apply_container_action_operation(operation)


func apply_container_action_operation(operation: Dictionary) -> Dictionary:
	var result: Dictionary = dictionary_or_empty(operation.get("result", {}))
	host.game_ui_coordinator.call("refresh_operation_panels", array_or_empty(operation.get("refresh", [])))
	return result


func has_active_container_session() -> bool:
	return not active_container_id().is_empty()


func drop_player_item(item_id: String, count: int = 1) -> Dictionary:
	var submit := Callable(self, "submit_inventory_action") if host.simulation != null else Callable()
	var operation: Dictionary = dictionary_or_empty(host.inventory_action_controller.call("drop_item", item_id, count, submit, Callable(self, "record_inventory_feedback")))
	return apply_inventory_action_operation(operation)


func deconstruct_player_item(item_id: String, count: int = 1) -> Dictionary:
	var submit := Callable(self, "submit_inventory_action") if host.simulation != null else Callable()
	var operation: Dictionary = dictionary_or_empty(host.inventory_action_controller.call("deconstruct_item", item_id, count, host.crafting_queue_coordinator.call("crafting_context"), submit, Callable(self, "record_inventory_feedback")))
	return apply_inventory_action_operation(operation)


func split_player_inventory_stack(item_id: String, count: int = 1, source_stack_index: int = 0) -> Dictionary:
	var submit := Callable(self, "submit_inventory_action") if host.simulation != null else Callable()
	var operation: Dictionary = dictionary_or_empty(host.inventory_action_controller.call("split_stack", item_id, count, source_stack_index, submit, Callable(self, "record_inventory_feedback")))
	return apply_inventory_action_operation(operation)


func reorder_player_inventory_item(item_id: String, target_index: int) -> Dictionary:
	var submit := Callable(self, "submit_inventory_action") if host.simulation != null else Callable()
	var operation: Dictionary = dictionary_or_empty(host.inventory_action_controller.call("reorder_item", item_id, target_index, submit, Callable(self, "record_inventory_feedback")))
	return apply_inventory_action_operation(operation)


func use_player_item(item_id: String) -> Dictionary:
	var submit := Callable(self, "submit_inventory_action") if host.simulation != null else Callable()
	var operation: Dictionary = dictionary_or_empty(host.inventory_action_controller.call("use_item", item_id, submit, Callable(self, "record_inventory_feedback")))
	return apply_inventory_action_operation(operation)


func apply_inventory_action_operation(operation: Dictionary) -> Dictionary:
	return apply_player_action_refresh_operation(operation)


func buy_active_trade_item(item_id: String, count: int = 1, stack_index: int = 0) -> Dictionary:
	var operation: Dictionary = dictionary_or_empty(host.trade_action_controller.call("buy_item", active_shop_id(), item_id, count, stack_index, Callable(self, "submit_inventory_action"), Callable(self, "record_trade_feedback")))
	return apply_trade_action_operation(operation)


func sell_active_trade_item(item_id: String, count: int = 1, stack_index: int = 0) -> Dictionary:
	var operation: Dictionary = dictionary_or_empty(host.trade_action_controller.call("sell_item", active_shop_id(), item_id, count, stack_index, Callable(self, "submit_inventory_action"), Callable(self, "record_trade_feedback")))
	return apply_trade_action_operation(operation)


func sell_active_trade_equipment(slot_id: String, item_id: String) -> Dictionary:
	var operation: Dictionary = dictionary_or_empty(host.trade_action_controller.call("sell_equipment", active_shop_id(), slot_id, item_id, Callable(self, "submit_inventory_action"), Callable(self, "record_trade_feedback")))
	return apply_trade_action_operation(operation)


func transfer_active_trade_item(source: String, item_id: String, count: int = 1, stack_index: int = 0) -> Dictionary:
	var operation: Dictionary = dictionary_or_empty(host.trade_action_controller.call("transfer_item", source, active_shop_id(), item_id, count, stack_index, Callable(self, "submit_inventory_action"), Callable(self, "record_trade_feedback")))
	return apply_trade_action_operation(operation)


func has_active_trade_session() -> bool:
	return not active_shop_id().is_empty()


func confirm_active_trade_cart(entries: Array) -> Dictionary:
	var operation: Dictionary = dictionary_or_empty(host.trade_action_controller.call("confirm_cart", entries, active_shop_id(), Callable(self, "confirm_trade_cart_action"), Callable(self, "record_trade_feedback")))
	return apply_trade_action_operation(operation)


func apply_trade_action_operation(operation: Dictionary) -> Dictionary:
	return apply_player_action_refresh_operation(operation)


func confirm_trade_cart_action(shop_id: String, entries: Array) -> Dictionary:
	if host.simulation == null or host.registry == null:
		return {"success": false, "reason": "simulation_missing"}
	return dictionary_or_empty(host.simulation.confirm_trade_cart(1, shop_id, entries, host.registry.get_library("items")))


func equip_player_item(item_id: String, slot_id: String) -> Dictionary:
	var submit := Callable(self, "submit_inventory_action") if host.simulation != null else Callable()
	var operation: Dictionary = dictionary_or_empty(host.character_action_controller.call("equip_item", item_id, slot_id, submit, Callable(self, "record_character_feedback")))
	return apply_character_action_operation(operation)


func unequip_player_slot(slot_id: String) -> Dictionary:
	var submit := Callable(self, "submit_inventory_action") if host.simulation != null else Callable()
	var operation: Dictionary = dictionary_or_empty(host.character_action_controller.call("unequip_slot", slot_id, submit, Callable(self, "record_character_feedback")))
	return apply_character_action_operation(operation)


func reload_player_equipped_slot(slot_id: String = "main_hand") -> Dictionary:
	var submit := Callable(self, "submit_inventory_action") if host.simulation != null else Callable()
	var operation: Dictionary = dictionary_or_empty(host.character_action_controller.call("reload_slot", slot_id, submit, Callable(self, "record_character_feedback")))
	return apply_character_action_operation(operation)


func allocate_player_attribute_point(attribute: String) -> Dictionary:
	var allocate := Callable(self, "allocate_attribute_action") if host.simulation != null else Callable()
	var operation: Dictionary = dictionary_or_empty(host.character_action_controller.call("allocate_attribute", attribute, allocate))
	return apply_character_action_operation(operation)


func apply_character_action_operation(operation: Dictionary) -> Dictionary:
	return apply_player_action_refresh_operation(operation)


func allocate_attribute_action(attribute: String) -> Dictionary:
	if host.simulation == null:
		return {"success": false, "reason": "simulation_missing"}
	return dictionary_or_empty(host.simulation.allocate_attribute_point(1, attribute))


func learn_player_skill(skill_id: String) -> Dictionary:
	if host.simulation == null:
		return {"success": false, "reason": "simulation_missing"}
	var blocked: Dictionary = dictionary_or_empty(host.player_command_coordinator.call("player_command_rejection", "learn_skill"))
	if not blocked.is_empty():
		return blocked
	var operation: Dictionary = dictionary_or_empty(host.skill_action_controller.call("learn_skill", skill_id, Callable(self, "submit_player_command_action"), host.registry.get_library("skills")))
	return apply_skill_action_operation(operation)


func bind_player_skill_to_hotbar(slot_id: String, skill_id: String) -> Dictionary:
	if host.simulation == null:
		return {"success": false, "reason": "simulation_missing"}
	var blocked: Dictionary = dictionary_or_empty(host.player_command_coordinator.call("player_command_rejection", "bind_hotbar"))
	if not blocked.is_empty():
		return blocked
	var operation: Dictionary = dictionary_or_empty(host.skill_action_controller.call("bind_skill_to_hotbar", slot_id, skill_id, Callable(self, "submit_player_command_action"), host.registry.get_library("skills")))
	return apply_skill_action_operation(operation)


func bind_player_item_to_hotbar(slot_id: String, item_id: String) -> Dictionary:
	if host.simulation == null:
		return {"success": false, "reason": "simulation_missing"}
	var blocked: Dictionary = dictionary_or_empty(host.player_command_coordinator.call("player_command_rejection", "bind_hotbar"))
	if not blocked.is_empty():
		return blocked
	var operation: Dictionary = dictionary_or_empty(host.skill_action_controller.call("bind_item_to_hotbar", slot_id, item_id, Callable(self, "submit_player_command_action"), host.registry.get_library("items"), host.registry.get_library("json")))
	return apply_skill_action_operation(operation)


func set_hotbar_group(group_id: String) -> Dictionary:
	if host.simulation == null:
		return {"success": false, "reason": "simulation_missing"}
	if bool(host.game_ui_coordinator.call("world_action_presenter_blocks_input")):
		return dictionary_or_empty(host.player_command_coordinator.call("action_presenter_command_rejected", "set_hotbar_group"))
	var set_group := Callable(host.simulation, "set_active_hotbar_group") if host.simulation.has_method("set_active_hotbar_group") else Callable()
	var operation: Dictionary = dictionary_or_empty(host.skill_action_controller.call("set_hotbar_group", group_id, set_group))
	return apply_skill_action_operation(operation)


func set_hotbar_group_label(group_id: String, label: String) -> Dictionary:
	if host.simulation == null:
		return {"success": false, "reason": "simulation_missing"}
	var set_label := Callable(host.simulation, "set_hotbar_group_label") if host.simulation.has_method("set_hotbar_group_label") else Callable()
	var operation: Dictionary = dictionary_or_empty(host.skill_action_controller.call("set_hotbar_group_label", group_id, label, set_label))
	return apply_skill_action_operation(operation)


func cycle_hotbar_group(direction: int) -> Dictionary:
	if host.simulation == null:
		return {"success": false, "reason": "simulation_missing"}
	if bool(host.game_ui_coordinator.call("world_action_presenter_blocks_input")):
		return dictionary_or_empty(host.player_command_coordinator.call("action_presenter_command_rejected", "cycle_hotbar_group"))
	var cycle_group := Callable(host.simulation, "cycle_hotbar_group") if host.simulation.has_method("cycle_hotbar_group") else Callable()
	var operation: Dictionary = dictionary_or_empty(host.skill_action_controller.call("cycle_hotbar_group", direction, cycle_group))
	return apply_skill_action_operation(operation)


func apply_skill_action_operation(operation: Dictionary) -> Dictionary:
	var result: Dictionary = dictionary_or_empty(operation.get("result", {}))
	if operation.has("target_markers") and host.runtime_input_controller != null and host.runtime_input_controller.has_method("update_skill_target_preview_markers"):
		host.runtime_input_controller.update_skill_target_preview_markers(dictionary_or_empty(operation.get("target_markers", {})))
	var selected_prompt: Dictionary = host.current_interaction_prompt() if bool(operation.get("selected_prompt", false)) else {}
	host.game_ui_coordinator.call("refresh_operation_panels", array_or_empty(operation.get("refresh", [])), selected_prompt)
	return result


func submit_player_command_action(command: Dictionary) -> Dictionary:
	if host.simulation == null:
		return {"success": false, "reason": "simulation_missing"}
	return dictionary_or_empty(host.simulation.submit_player_command(command))


func preview_skill_target_action(skill_id: String, target: Dictionary) -> Dictionary:
	if host.simulation == null:
		return {"success": false, "reason": "simulation_missing"}
	return dictionary_or_empty(host.simulation.preview_skill_target(1, skill_id, host.registry.get_library("skills"), target, dictionary_or_empty(host.world_result.get("map", {}))))


func use_hotbar_slot(slot_id: String) -> Dictionary:
	if host.simulation == null:
		return {"success": false, "reason": "simulation_missing"}
	var blocked: Dictionary = dictionary_or_empty(host.player_command_coordinator.call("player_command_rejection", "hotbar"))
	if not blocked.is_empty():
		return blocked
	var operation: Dictionary = dictionary_or_empty(host.skill_action_controller.call(
		"use_hotbar_slot",
		slot_id,
		host.simulation.snapshot(),
		host.registry.get_library("skills"),
		host.registry.get_library("items"),
		host.registry.get_library("json"),
		Callable(self, "submit_player_command_action"),
		Callable(self, "submit_inventory_action"),
		host.skill_targeting_controller
	))
	return apply_skill_action_operation(operation)


func begin_skill_targeting(slot_id: String, skill_id: String = "") -> Dictionary:
	if host.simulation == null:
		return {"success": false, "reason": "simulation_missing"}
	var blocked: Dictionary = dictionary_or_empty(host.player_command_coordinator.call("player_command_rejection", "use_skill"))
	if not blocked.is_empty():
		return blocked
	var operation: Dictionary = dictionary_or_empty(host.skill_action_controller.call(
		"begin_skill_targeting",
		slot_id,
		skill_id,
		host.simulation.snapshot(),
		host.registry.get_library("skills"),
		Callable(self, "submit_player_command_action"),
		host.skill_targeting_controller
	))
	return apply_skill_action_operation(operation)


func preview_active_skill_target(target: Dictionary) -> Dictionary:
	var operation: Dictionary = dictionary_or_empty(host.skill_action_controller.call(
		"preview_active_skill_target",
		target,
		Callable(self, "preview_skill_target_action") if host.simulation != null else Callable(),
		host.skill_targeting_controller
	))
	return apply_skill_action_operation(operation)


func confirm_active_skill_target(target: Dictionary = {}) -> Dictionary:
	if host.simulation == null:
		return {"success": false, "reason": "skill_targeting_inactive"}
	var blocked: Dictionary = dictionary_or_empty(host.player_command_coordinator.call("player_command_rejection", "use_skill"))
	if not blocked.is_empty():
		return blocked
	var operation: Dictionary = dictionary_or_empty(host.skill_action_controller.call(
		"confirm_active_skill_target",
		target,
		Callable(self, "submit_player_command_action"),
		host.registry.get_library("skills"),
		dictionary_or_empty(host.world_result.get("map", {})),
		host.skill_targeting_controller
	))
	return apply_skill_action_operation(operation)


func cancel_active_skill_targeting(reason: String = "cancelled") -> Dictionary:
	var operation: Dictionary = dictionary_or_empty(host.skill_action_controller.call("cancel_active_skill_targeting", reason, host.skill_targeting_controller))
	return apply_skill_action_operation(operation)


func has_active_skill_targeting() -> bool:
	return bool(host.skill_targeting_controller.call("has_active_targeting"))


func active_skill_targeting_snapshot() -> Dictionary:
	return dictionary_or_empty(host.skill_targeting_controller.call("snapshot"))


func turn_in_player_quest(quest_id: String) -> Dictionary:
	var operation: Dictionary = dictionary_or_empty(host.world_panel_action_controller.call(
		"turn_in_quest",
		quest_id,
		Callable(self, "turn_in_quest_action") if host.simulation != null else Callable()
	))
	return apply_world_panel_action_operation(operation)


func enter_overworld_location_from_panel(location_id: String) -> Dictionary:
	var operation: Dictionary = dictionary_or_empty(host.world_panel_action_controller.call(
		"enter_overworld_location",
		location_id,
		Callable(self, "enter_overworld_location_action") if host.simulation != null else Callable()
	))
	return apply_world_panel_action_operation(operation)


func turn_in_quest_action(quest_id: String) -> Dictionary:
	if host.simulation == null:
		return {"success": false, "reason": "simulation_missing"}
	return dictionary_or_empty(host.simulation.turn_in_quest(1, quest_id))


func enter_overworld_location_action(location_id: String) -> Dictionary:
	if host.simulation == null:
		return {"success": false, "reason": "simulation_missing", "location_id": location_id}
	return dictionary_or_empty(host.simulation.enter_location(1, location_id, host.registry.get_library("overworld")))


func apply_world_panel_action_operation(operation: Dictionary) -> Dictionary:
	return apply_player_action_refresh_operation(operation, host.current_interaction_prompt(), dictionary_or_empty(operation.get("result", {})), {})


func submit_inventory_action(action: Dictionary) -> Dictionary:
	if host.simulation == null:
		return {"success": false, "reason": "simulation_missing"}
	var blocked: Dictionary = player_command_rejection(str(action.get("action", "inventory_action")))
	if not blocked.is_empty():
		return blocked
	var command: Dictionary = action.duplicate(true)
	command["kind"] = "inventory_action"
	command["actor_id"] = 1
	command["item_library"] = host.registry.get_library("items")
	command["effect_library"] = host.registry.get_library("json")
	command["topology"] = dictionary_or_empty(host.world_result.get("map", {}))
	return host.simulation.submit_player_command(command)


func player_command_rejection(action: String) -> Dictionary:
	var modal_name := str(host.game_ui_coordinator.call("panel_modal_blocker_name"))
	var result: Dictionary = dictionary_or_empty(host.player_command_blocker.call(
		"player_command_rejection",
		action,
		host.is_observe_mode_enabled(),
		modal_name,
		bool(host.game_ui_coordinator.call("world_action_presenter_blocks_input")),
		host.gameplay_input_blocker_snapshot()
	))
	if not result.is_empty():
		host.refresh_hud(host.current_interaction_prompt())
	return result


func observe_command_rejected(action: String) -> Dictionary:
	var result: Dictionary = dictionary_or_empty(host.player_command_blocker.call("observe_command_rejected", action, host.is_observe_mode_enabled()))
	host.refresh_hud(host.current_interaction_prompt())
	return result


func action_presenter_command_rejected(action: String) -> Dictionary:
	var blocker: Dictionary = host.gameplay_input_blocker_snapshot()
	var result: Dictionary = dictionary_or_empty(host.player_command_blocker.call("action_presenter_command_rejected", action, blocker))
	host.refresh_hud(host.current_interaction_prompt())
	return result


func ui_modal_command_rejected(action: String, modal_name: String) -> Dictionary:
	var blocker: Dictionary = host.gameplay_input_blocker_snapshot()
	var result: Dictionary = dictionary_or_empty(host.player_command_blocker.call("ui_modal_command_rejected", action, modal_name, blocker))
	host.refresh_hud(host.current_interaction_prompt())
	return result


func record_container_feedback(result: Dictionary, action: String, container_id: String, item_id: String, count: int) -> void:
	host.ui_feedback_state_controller.call("record_container_feedback", result, action, container_id, item_id, count)


func record_trade_feedback(result: Dictionary, action: String, shop_id: String, item_id: String, count: int) -> void:
	host.ui_feedback_state_controller.call("record_trade_feedback", result, action, shop_id, item_id, count)


func record_inventory_feedback(result: Dictionary, action: String, item_id: String, count: int) -> void:
	host.ui_feedback_state_controller.call("record_inventory_feedback", result, action, item_id, count)


func record_character_feedback(result: Dictionary, action: String, slot_id: String, item_id: String) -> void:
	host.ui_feedback_state_controller.call("record_character_feedback", result, action, slot_id, item_id)


func apply_player_action_refresh_operation(operation: Dictionary, selected_prompt: Dictionary = {}, rebuild_command_result: Dictionary = {}, rebuild_selected_prompt: Variant = null) -> Dictionary:
	return dictionary_or_empty(host.player_action_refresh_controller.call(
		"apply_operation",
		operation,
		selected_prompt,
		rebuild_command_result,
		rebuild_selected_prompt,
		Callable(host, "rebuild_runtime_world"),
		Callable(host, "refresh_all_panels"),
		Callable(host.game_ui_coordinator, "refresh_operation_panels")
	))


func current_dialogue_snapshot() -> Dictionary:
	if host.simulation == null:
		return {}
	var DialogueSnapshot = preload("res://scripts/ui/snapshots/dialogue_snapshot.gd")
	return DialogueSnapshot.new(host.registry).build(host.simulation.ui_runtime_view())


func active_shop_id() -> String:
	return str(host.runtime_session_context_controller.call("active_shop_id", host.registry, host.simulation, host.active_trade_target))


func trade_closed_payload(target: Dictionary, reason: String) -> Dictionary:
	return dictionary_or_empty(host.runtime_session_context_controller.call("trade_closed_payload", host.registry, host.simulation, target, reason))


func active_container_id() -> String:
	return str(host.runtime_session_context_controller.call("active_container_id", host.simulation))


func dictionary_or_empty(value: Variant) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}


func array_or_empty(value: Variant) -> Array:
	return value if typeof(value) == TYPE_ARRAY else []
