extends RefCounted

const ACTION_MENU_INVENTORY: StringName = &"menu_inventory"
const ACTION_MENU_CHARACTER: StringName = &"menu_character"
const ACTION_MENU_MAP: StringName = &"menu_map"
const ACTION_MENU_JOURNAL: StringName = &"menu_journal"
const ACTION_MENU_SKILLS: StringName = &"menu_skills"
const ACTION_MENU_CRAFTING: StringName = &"menu_crafting"
const ACTION_MENU_SETTINGS: StringName = &"menu_settings"

const ACTION_HOTBAR_1: StringName = &"hotbar_slot_1"
const ACTION_HOTBAR_2: StringName = &"hotbar_slot_2"
const ACTION_HOTBAR_3: StringName = &"hotbar_slot_3"
const ACTION_HOTBAR_4: StringName = &"hotbar_slot_4"
const ACTION_HOTBAR_5: StringName = &"hotbar_slot_5"
const ACTION_HOTBAR_6: StringName = &"hotbar_slot_6"
const ACTION_HOTBAR_7: StringName = &"hotbar_slot_7"
const ACTION_HOTBAR_8: StringName = &"hotbar_slot_8"
const ACTION_HOTBAR_9: StringName = &"hotbar_slot_9"
const ACTION_HOTBAR_10: StringName = &"hotbar_slot_10"

const MENU_ACTIONS: Array[StringName] = [
	ACTION_MENU_INVENTORY,
	ACTION_MENU_CHARACTER,
	ACTION_MENU_MAP,
	ACTION_MENU_JOURNAL,
	ACTION_MENU_SKILLS,
	ACTION_MENU_CRAFTING,
	ACTION_MENU_SETTINGS
]

const HOTBAR_ACTIONS: Array[StringName] = [
	ACTION_HOTBAR_1,
	ACTION_HOTBAR_2,
	ACTION_HOTBAR_3,
	ACTION_HOTBAR_4,
	ACTION_HOTBAR_5,
	ACTION_HOTBAR_6,
	ACTION_HOTBAR_7,
	ACTION_HOTBAR_8,
	ACTION_HOTBAR_9,
	ACTION_HOTBAR_10
]

const ALL_ACTIONS: Array[StringName] = MENU_ACTIONS + HOTBAR_ACTIONS

const REBINDABLE_ACTIONS: Array[StringName] = [
	ACTION_MENU_INVENTORY,
	ACTION_MENU_CHARACTER,
	ACTION_MENU_MAP,
	ACTION_MENU_JOURNAL,
	ACTION_MENU_SKILLS,
	ACTION_MENU_CRAFTING
]

const ACTION_LABELS: Dictionary = {
	ACTION_MENU_INVENTORY: "背包与装备",
	ACTION_MENU_CHARACTER: "角色面板",
	ACTION_MENU_MAP: "地图",
	ACTION_MENU_JOURNAL: "任务面板",
	ACTION_MENU_SKILLS: "技能面板",
	ACTION_MENU_CRAFTING: "制造面板",
	ACTION_MENU_SETTINGS: "设置面板"
}

const DEFAULT_BINDINGS: Dictionary = {
	ACTION_MENU_INVENTORY: KEY_I,
	ACTION_MENU_CHARACTER: KEY_C,
	ACTION_MENU_MAP: KEY_M,
	ACTION_MENU_JOURNAL: KEY_J,
	ACTION_MENU_SKILLS: KEY_K,
	ACTION_MENU_CRAFTING: KEY_L,
	ACTION_MENU_SETTINGS: KEY_ESCAPE,
	ACTION_HOTBAR_1: KEY_1,
	ACTION_HOTBAR_2: KEY_2,
	ACTION_HOTBAR_3: KEY_3,
	ACTION_HOTBAR_4: KEY_4,
	ACTION_HOTBAR_5: KEY_5,
	ACTION_HOTBAR_6: KEY_6,
	ACTION_HOTBAR_7: KEY_7,
	ACTION_HOTBAR_8: KEY_8,
	ACTION_HOTBAR_9: KEY_9,
	ACTION_HOTBAR_10: KEY_0
}


static func ensure_actions_registered() -> void:
	for action_variant in ALL_ACTIONS:
		var action: StringName = action_variant
		if not InputMap.has_action(action):
			InputMap.add_action(action)

	for action_variant in DEFAULT_BINDINGS.keys():
		var action_name: StringName = action_variant
		if InputMap.action_get_events(action_name).is_empty():
			var keycode: int = int(DEFAULT_BINDINGS[action_name])
			apply_binding(action_name, keycode, keycode)


static func apply_binding(action_name: StringName, keycode: int, physical_keycode: int = -1) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)

	InputMap.action_erase_events(action_name)
	var key_event := InputEventKey.new()
	key_event.keycode = keycode
	key_event.physical_keycode = physical_keycode if physical_keycode >= 0 else keycode
	InputMap.action_add_event(action_name, key_event)


static func get_current_binding(action_name: StringName) -> Dictionary:
	var events: Array[InputEvent] = InputMap.action_get_events(action_name)
	for event in events:
		if event is InputEventKey:
			var key_event: InputEventKey = event as InputEventKey
			return {
				"keycode": int(key_event.keycode),
				"physical_keycode": int(key_event.physical_keycode)
			}

	var default_key: int = int(DEFAULT_BINDINGS.get(action_name, KEY_NONE))
	return {
		"keycode": default_key,
		"physical_keycode": default_key
	}


static func get_hotbar_action_for_slot(slot_index: int) -> StringName:
	if slot_index < 0 or slot_index >= HOTBAR_ACTIONS.size():
		return StringName()
	return HOTBAR_ACTIONS[slot_index]


static func get_hotbar_slot_for_event(event: InputEvent) -> int:
	for index in range(HOTBAR_ACTIONS.size()):
		if event.is_action_pressed(HOTBAR_ACTIONS[index]):
			return index
	return -1


static func keycode_to_text(keycode: int) -> String:
	if keycode == KEY_NONE:
		return "未绑定"
	return OS.get_keycode_string(keycode)


static func get_action_label(action_name: StringName) -> String:
	return str(ACTION_LABELS.get(action_name, action_name))
