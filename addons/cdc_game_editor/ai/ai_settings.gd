@tool
extends RefCounted

const KEY_BASE_URL := "cdc_game_editor/ai/base_url"
const KEY_MODEL := "cdc_game_editor/ai/model"
const KEY_API_KEY := "cdc_game_editor/ai/api_key"
const KEY_TIMEOUT_SEC := "cdc_game_editor/ai/timeout_sec"
const KEY_MAX_CONTEXT_RECORDS := "cdc_game_editor/ai/max_context_records"

const DEFAULT_BASE_URL := "https://api.openai.com/v1"
const DEFAULT_MODEL := "gpt-4.1-mini"
const DEFAULT_TIMEOUT_SEC := 45
const DEFAULT_MAX_CONTEXT_RECORDS := 24

static func get_provider_config(editor_plugin: EditorPlugin = null) -> Dictionary:
	return {
		"base_url": get_base_url(editor_plugin),
		"model": get_model(editor_plugin),
		"api_key": get_api_key(editor_plugin),
		"timeout_sec": get_timeout_sec(editor_plugin)
	}


static func get_base_url(editor_plugin: EditorPlugin = null) -> String:
	return str(_get_setting(editor_plugin, KEY_BASE_URL, DEFAULT_BASE_URL)).strip_edges()


static func get_model(editor_plugin: EditorPlugin = null) -> String:
	return str(_get_setting(editor_plugin, KEY_MODEL, DEFAULT_MODEL)).strip_edges()


static func get_api_key(editor_plugin: EditorPlugin = null) -> String:
	var configured_key := str(_get_setting(editor_plugin, KEY_API_KEY, "")).strip_edges()
	if not configured_key.is_empty():
		return configured_key

	for env_key in ["OPENAI_API_KEY", "AI_API_KEY"]:
		var env_value := OS.get_environment(env_key).strip_edges()
		if not env_value.is_empty():
			return env_value
	return ""


static func get_timeout_sec(editor_plugin: EditorPlugin = null) -> int:
	return max(int(_get_setting(editor_plugin, KEY_TIMEOUT_SEC, DEFAULT_TIMEOUT_SEC)), 5)


static func get_max_context_records(editor_plugin: EditorPlugin = null) -> int:
	return max(int(_get_setting(editor_plugin, KEY_MAX_CONTEXT_RECORDS, DEFAULT_MAX_CONTEXT_RECORDS)), 6)


static func set_provider_config(editor_plugin: EditorPlugin, config: Dictionary) -> bool:
	if editor_plugin == null:
		return false
	var ok := true
	ok = set_setting(editor_plugin, KEY_BASE_URL, str(config.get("base_url", DEFAULT_BASE_URL)).strip_edges()) and ok
	ok = set_setting(editor_plugin, KEY_MODEL, str(config.get("model", DEFAULT_MODEL)).strip_edges()) and ok
	ok = set_setting(editor_plugin, KEY_API_KEY, str(config.get("api_key", "")).strip_edges()) and ok
	ok = set_setting(editor_plugin, KEY_TIMEOUT_SEC, int(config.get("timeout_sec", DEFAULT_TIMEOUT_SEC))) and ok
	ok = set_setting(
		editor_plugin,
		KEY_MAX_CONTEXT_RECORDS,
		int(config.get("max_context_records", DEFAULT_MAX_CONTEXT_RECORDS))
	) and ok
	return ok


static func set_setting(editor_plugin: EditorPlugin, key: String, value: Variant) -> bool:
	var settings := _get_editor_settings(editor_plugin)
	if settings == null:
		return false
	settings.set_setting(key, value)
	return true


static func _get_setting(editor_plugin: EditorPlugin, key: String, default_value: Variant) -> Variant:
	var settings := _get_editor_settings(editor_plugin)
	if settings == null:
		return default_value
	if settings.has_setting(key):
		return settings.get_setting(key)
	return default_value


static func _get_editor_settings(editor_plugin: EditorPlugin) -> EditorSettings:
	if editor_plugin == null:
		return null
	var editor_interface := editor_plugin.get_editor_interface()
	if editor_interface == null:
		return null
	return editor_interface.get_editor_settings()
