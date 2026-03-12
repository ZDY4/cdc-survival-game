extends RefCounted

const ACTION_MENU_INVENTORY: StringName = &"menu_inventory"
const ACTION_MENU_CHARACTER: StringName = &"menu_character"
const ACTION_MENU_MAP: StringName = &"menu_map"
const ACTION_MENU_JOURNAL: StringName = &"menu_journal"
const ACTION_MENU_SKILLS: StringName = &"menu_skills"
const ACTION_MENU_CRAFTING: StringName = &"menu_crafting"
const ACTION_MENU_SETTINGS: StringName = &"menu_settings"

const MENU_ACTIONS: Array[StringName] = [
	ACTION_MENU_INVENTORY,
	ACTION_MENU_CHARACTER,
	ACTION_MENU_MAP,
	ACTION_MENU_JOURNAL,
	ACTION_MENU_SKILLS,
	ACTION_MENU_CRAFTING,
	ACTION_MENU_SETTINGS
]

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
	ACTION_MENU_SETTINGS: KEY_ESCAPE
}

static func ensure_actions_registered() -> void:
	for action_variant in MENU_ACTIONS:
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

static func keycode_to_text(keycode: int) -> String:
	if keycode == KEY_NONE:
		return "未绑定"
	return OS.get_keycode_string(keycode)

static func get_action_label(action_name: StringName) -> String:
	return str(ACTION_LABELS.get(action_name, action_name))
