extends RefCounted

const PLAYER_COMMAND_AUTHORITY_AUDIT: Array[Dictionary] = [
	{"app_method": "execute_primary_interaction", "owner_method": "execute_primary", "action": "interact", "authority_kind": "submit_player_command", "command_kind": "interact", "owner": "InteractionActionController", "blocker": "_player_command_rejection"},
	{"app_method": "execute_interaction_option", "owner_method": "execute_option", "action": "interact_option", "authority_kind": "submit_player_command", "command_kind": "interact", "owner": "InteractionActionController", "blocker": "_player_command_rejection"},
	{"app_method": "execute_move_to_grid", "owner_method": "execute_move", "action": "move", "authority_kind": "submit_player_command", "command_kind": "move", "owner": "InteractionActionController", "blocker": "_player_command_rejection"},
	{"app_method": "press_space_action", "owner_method": "press_space_action", "action": "wait_or_dialogue_advance", "authority_kind": "mixed", "command_kind": "wait", "core_service": "advance_dialogue.call", "owner": "WaitActionController", "blocker": "dialogue_or_pending_or_command"},
	{"app_method": "_submit_auto_tick_wait", "owner_method": "auto_tick_wait", "action": "auto_wait", "authority_kind": "submit_player_command", "command_kind": "wait", "owner": "WaitActionController", "blocker": "ui_or_pending"},
	{"app_method": "choose_dialogue_option", "owner_method": "choose_option", "action": "dialogue_choice", "authority_kind": "core_service", "core_service": "Simulation.advance_dialogue", "owner": "DialogueActionController", "blocker": "dialogue_session"},
	{"app_method": "advance_dialogue_without_choice", "owner_method": "continue_without_choice", "action": "dialogue_continue", "authority_kind": "core_service", "core_service": "Simulation.advance_dialogue_without_choice", "owner": "DialogueActionController", "blocker": "dialogue_session"},
	{"app_method": "close_active_dialogue", "owner_method": "close_dialogue", "action": "dialogue_close", "authority_kind": "core_service", "core_service": "Simulation.close_dialogue", "owner": "DialogueActionController", "blocker": "dialogue_session"},
	{"app_method": "close_active_container", "owner_method": "close_container", "action": "container_close", "authority_kind": "core_service", "core_service": "Simulation.close_container", "owner": "ContainerActionController", "blocker": "container_session"},
	{"app_method": "take_active_container_item", "owner_method": "take_item", "action": "take_container", "authority_kind": "submit_player_command", "command_kind": "inventory_action", "inventory_action": "take_container", "owner": "ContainerActionController", "blocker": "_submit_inventory_action"},
	{"app_method": "take_active_container_money", "owner_method": "take_money", "action": "take_container_money", "authority_kind": "submit_player_command", "command_kind": "inventory_action", "inventory_action": "take_container_money", "owner": "ContainerActionController", "blocker": "_submit_inventory_action"},
	{"app_method": "take_all_active_container_items", "owner_method": "take_all", "action": "take_all_container", "authority_kind": "submit_player_command", "command_kind": "inventory_action", "inventory_action": "take_all_container", "owner": "ContainerActionController", "blocker": "_submit_inventory_action"},
	{"app_method": "store_active_container_item", "owner_method": "store_item", "action": "store_container", "authority_kind": "submit_player_command", "command_kind": "inventory_action", "inventory_action": "store_container", "owner": "ContainerActionController", "blocker": "_submit_inventory_action"},
	{"app_method": "store_all_active_container_items", "owner_method": "store_all", "action": "store_all_container", "authority_kind": "submit_player_command", "command_kind": "inventory_action", "inventory_action": "store_all_container", "owner": "ContainerActionController", "blocker": "_submit_inventory_action"},
	{"app_method": "drop_player_item", "owner_method": "drop_item", "action": "drop_item", "authority_kind": "submit_player_command", "command_kind": "inventory_action", "inventory_action": "drop", "owner": "InventoryActionController", "blocker": "_submit_inventory_action"},
	{"app_method": "deconstruct_player_item", "owner_method": "deconstruct_item", "action": "deconstruct_item", "authority_kind": "submit_player_command", "command_kind": "inventory_action", "inventory_action": "deconstruct", "owner": "InventoryActionController", "blocker": "_submit_inventory_action"},
	{"app_method": "split_player_inventory_stack", "owner_method": "split_stack", "action": "split_stack", "authority_kind": "submit_player_command", "command_kind": "inventory_action", "inventory_action": "split_stack", "owner": "InventoryActionController", "blocker": "_submit_inventory_action"},
	{"app_method": "reorder_player_inventory_item", "owner_method": "reorder_item", "action": "reorder_inventory", "authority_kind": "submit_player_command", "command_kind": "inventory_action", "inventory_action": "reorder_inventory", "owner": "InventoryActionController", "blocker": "_submit_inventory_action"},
	{"app_method": "use_player_item", "owner_method": "use_item", "action": "use_item", "authority_kind": "submit_player_command", "command_kind": "inventory_action", "inventory_action": "use_item", "owner": "InventoryActionController", "blocker": "_submit_inventory_action"},
	{"app_method": "buy_active_trade_item", "owner_method": "buy_item", "action": "buy_shop", "authority_kind": "submit_player_command", "command_kind": "inventory_action", "inventory_action": "buy_shop", "owner": "TradeActionController", "blocker": "_submit_inventory_action"},
	{"app_method": "sell_active_trade_item", "owner_method": "sell_item", "action": "sell_shop", "authority_kind": "submit_player_command", "command_kind": "inventory_action", "inventory_action": "sell_shop", "owner": "TradeActionController", "blocker": "_submit_inventory_action"},
	{"app_method": "sell_active_trade_equipment", "owner_method": "sell_equipment", "action": "sell_equipped_shop", "authority_kind": "submit_player_command", "command_kind": "inventory_action", "inventory_action": "sell_equipped_shop", "owner": "TradeActionController", "blocker": "_submit_inventory_action"},
	{"app_method": "confirm_active_trade_cart", "owner_method": "confirm_cart", "action": "trade_cart", "authority_kind": "core_service", "core_service": "Simulation.confirm_trade_cart", "owner": "TradeActionController", "blocker": "trade_session"},
	{"app_method": "equip_player_item", "owner_method": "equip_item", "action": "equip", "authority_kind": "submit_player_command", "command_kind": "inventory_action", "inventory_action": "equip", "owner": "CharacterActionController", "blocker": "_submit_inventory_action"},
	{"app_method": "unequip_player_slot", "owner_method": "unequip_slot", "action": "unequip", "authority_kind": "submit_player_command", "command_kind": "inventory_action", "inventory_action": "unequip", "owner": "CharacterActionController", "blocker": "_submit_inventory_action"},
	{"app_method": "reload_player_equipped_slot", "owner_method": "reload_slot", "action": "reload_equipped", "authority_kind": "submit_player_command", "command_kind": "inventory_action", "inventory_action": "reload_equipped", "owner": "CharacterActionController", "blocker": "_submit_inventory_action"},
	{"app_method": "allocate_player_attribute_point", "owner_method": "allocate_attribute", "action": "allocate_attribute", "authority_kind": "core_service", "core_service": "Simulation.allocate_attribute_point", "owner": "CharacterActionController", "blocker": "attribute_points"},
	{"app_method": "learn_player_skill", "owner_method": "learn_skill", "action": "learn_skill", "authority_kind": "submit_player_command", "command_kind": "learn_skill", "owner": "SkillActionController", "blocker": "_player_command_rejection"},
	{"app_method": "bind_player_skill_to_hotbar", "owner_method": "bind_skill_to_hotbar", "action": "bind_skill_hotbar", "authority_kind": "submit_player_command", "command_kind": "bind_hotbar", "owner": "SkillActionController", "blocker": "_player_command_rejection"},
	{"app_method": "bind_player_item_to_hotbar", "owner_method": "bind_item_to_hotbar", "action": "bind_item_hotbar", "authority_kind": "submit_player_command", "command_kind": "bind_hotbar", "owner": "SkillActionController", "blocker": "_player_command_rejection"},
	{"app_method": "set_hotbar_group", "owner_method": "set_hotbar_group", "action": "set_hotbar_group", "authority_kind": "core_service", "core_service": "Simulation.set_active_hotbar_group", "owner": "SkillActionController", "blocker": "world_action_presenter"},
	{"app_method": "set_hotbar_group_label", "owner_method": "set_hotbar_group_label", "action": "set_hotbar_group_label", "authority_kind": "core_service", "core_service": "Simulation.set_hotbar_group_label", "owner": "SkillActionController", "blocker": "hotbar_group"},
	{"app_method": "cycle_hotbar_group", "owner_method": "cycle_hotbar_group", "action": "cycle_hotbar_group", "authority_kind": "core_service", "core_service": "Simulation.cycle_hotbar_group", "owner": "SkillActionController", "blocker": "world_action_presenter"},
	{"app_method": "use_hotbar_slot", "action": "use_hotbar", "authority_kind": "submit_player_command", "command_kind": "use_skill_or_inventory_action", "owner": "SkillActionController", "blocker": "_player_command_rejection"},
	{"app_method": "begin_skill_targeting", "action": "begin_skill_targeting", "authority_kind": "submit_player_command_or_ui_state", "command_kind": "use_skill", "owner": "SkillActionController", "blocker": "_player_command_rejection", "state_owner": "SkillTargetingController"},
	{"app_method": "confirm_active_skill_target", "action": "confirm_skill_target", "authority_kind": "submit_player_command", "command_kind": "use_skill", "owner": "SkillActionController", "blocker": "_player_command_rejection", "state_owner": "SkillTargetingController"},
	{"app_method": "craft_player_recipe", "owner_method": "craft_recipe", "action": "craft", "authority_kind": "submit_player_command", "command_kind": "craft", "owner": "CraftingActionController", "blocker": "_player_command_rejection"},
	{"app_method": "confirm_crafting_queue", "owner_method": "confirm_queue", "action": "crafting_queue", "authority_kind": "submit_player_command", "command_kind": "craft", "owner": "CraftingActionController", "blocker": "_player_command_rejection", "authority_helper": "advance_queue"},
	{"app_method": "cancel_pending_crafting", "owner_method": "cancel_pending", "action": "cancel_pending_crafting", "authority_kind": "submit_player_command", "command_kind": "cancel_pending", "owner": "CraftingActionController", "blocker": "pending_crafting"},
	{"app_method": "turn_in_player_quest", "owner_method": "turn_in_quest", "action": "quest_turn_in", "authority_kind": "core_service", "core_service": "Simulation.turn_in_quest", "owner": "WorldPanelActionController", "blocker": "quest_state"},
	{"app_method": "enter_overworld_location_from_panel", "owner_method": "enter_overworld_location", "action": "enter_overworld_location", "authority_kind": "core_service", "core_service": "Simulation.enter_location", "owner": "WorldPanelActionController", "blocker": "map_panel_prompt"},
]


func snapshot(debug_runtime_controller: RefCounted, game_root: Node) -> Dictionary:
	var allowed_authority_kinds := [
		"submit_player_command",
		"core_service",
		"mixed",
		"submit_player_command_or_ui_state",
	]
	var entries: Array[Dictionary] = []
	var unknown_authority: Array[Dictionary] = []
	var missing_command_kind: Array[Dictionary] = []
	var missing_core_service: Array[Dictionary] = []
	var command_count := 0
	var core_service_count := 0
	var mixed_count := 0
	for entry in PLAYER_COMMAND_AUTHORITY_AUDIT:
		var item := entry.duplicate(true)
		var authority_kind := str(item.get("authority_kind", ""))
		var command_kind := str(item.get("command_kind", ""))
		var core_service := str(item.get("core_service", ""))
		item["authority_helper"] = str(item.get("authority_helper", ""))
		if not allowed_authority_kinds.has(authority_kind):
			unknown_authority.append(item.duplicate(true))
		if authority_kind == "submit_player_command" or authority_kind == "submit_player_command_or_ui_state":
			command_count += 1
			if command_kind.is_empty():
				missing_command_kind.append(item.duplicate(true))
		elif authority_kind == "core_service":
			core_service_count += 1
			if core_service.is_empty():
				missing_core_service.append(item.duplicate(true))
		elif authority_kind == "mixed":
			mixed_count += 1
			if command_kind.is_empty():
				missing_command_kind.append(item.duplicate(true))
			if core_service.is_empty():
				missing_core_service.append(item.duplicate(true))
		entries.append(item)
	return {
		"audit_version": 2,
		"requires_simulation_authority": true,
		"business_entry_count": entries.size(),
		"submit_player_command_entry_count": command_count,
		"core_service_entry_count": core_service_count,
		"mixed_entry_count": mixed_count,
		"allowed_authority_kinds": allowed_authority_kinds,
		"unknown_authority_count": unknown_authority.size(),
		"missing_command_kind_count": missing_command_kind.size(),
		"missing_core_service_count": missing_core_service.size(),
		"unknown_authority": unknown_authority,
		"missing_command_kind": missing_command_kind,
		"missing_core_service": missing_core_service,
		"entries": entries,
		"debug_console_mutation_audit": debug_console_mutation_authority_audit(debug_runtime_controller, game_root),
	}


func debug_console_mutation_authority_audit(debug_runtime_controller: RefCounted, game_root: Node) -> Dictionary:
	var mutating_commands: Array[Dictionary] = []
	var missing_permission: Array[Dictionary] = []
	var missing_runtime_flag: Array[Dictionary] = []
	var missing_usage: Array[Dictionary] = []
	var permission_snapshot: Dictionary = debug_runtime_controller.permission_snapshot(game_root)
	for command in debug_runtime_controller.command_schema():
		var command_data: Dictionary = _dictionary_or_empty(command).duplicate(true)
		if not bool(command_data.get("mutates_runtime", false)):
			continue
		var permission := str(command_data.get("permission", "")).strip_edges()
		var usage := str(command_data.get("usage", "")).strip_edges()
		var item := {
			"id": str(command_data.get("id", usage)),
			"usage": usage,
			"permission": permission,
			"mutates_runtime": true,
			"authority_kind": "debug_console_runtime_mutation",
			"runner": "DebugConsoleCommandRunner",
		}
		if permission != "debug_runtime_mutation":
			missing_permission.append(item.duplicate(true))
		if not bool(command_data.get("mutates_runtime", false)):
			missing_runtime_flag.append(item.duplicate(true))
		if usage.is_empty():
			missing_usage.append(item.duplicate(true))
		mutating_commands.append(item)
	return {
		"authority_kind": "debug_console_runtime_mutation",
		"runner": "DebugConsoleCommandRunner",
		"permission": "debug_runtime_mutation",
		"runtime_mutation_setting": str(permission_snapshot.get("runtime_mutation_setting", "")),
		"allow_runtime_mutation": bool(permission_snapshot.get("allow_runtime_mutation", false)),
		"mutating_command_count": mutating_commands.size(),
		"schema_mutating_command_count": int(permission_snapshot.get("mutating_command_count", 0)),
		"missing_permission_count": missing_permission.size(),
		"missing_runtime_flag_count": missing_runtime_flag.size(),
		"missing_usage_count": missing_usage.size(),
		"commands": mutating_commands,
		"missing_permission": missing_permission,
		"missing_runtime_flag": missing_runtime_flag,
		"missing_usage": missing_usage,
	}


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}
