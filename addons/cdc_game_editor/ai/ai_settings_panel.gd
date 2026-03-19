@tool
extends Control

const AI_SETTINGS := preload("res://addons/cdc_game_editor/ai/ai_settings.gd")
const OPENAI_PROVIDER_SCRIPT := preload("res://addons/cdc_game_editor/ai/providers/openai_compatible_provider.gd")

var editor_plugin: EditorPlugin = null

var _provider: Node = null
var _base_url_input: LineEdit
var _model_input: LineEdit
var _api_key_input: LineEdit
var _timeout_input: SpinBox
var _max_context_input: SpinBox
var _status_label: Label
var _test_result_output: TextEdit
var _last_test_meta: Dictionary = {}


func _ready() -> void:
	_provider = OPENAI_PROVIDER_SCRIPT.new()
	add_child(_provider)
	_build_ui()
	_load_settings()


func _build_ui() -> void:
	anchors_preset = Control.PRESET_FULL_RECT
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 16
	root.offset_top = 16
	root.offset_right = -16
	root.offset_bottom = -16
	root.add_theme_constant_override("separation", 10)
	add_child(root)

	var grid := GridContainer.new()
	grid.columns = 2
	root.add_child(grid)

	grid.add_child(_make_label("Base URL"))
	_base_url_input = LineEdit.new()
	grid.add_child(_base_url_input)

	grid.add_child(_make_label("Model"))
	_model_input = LineEdit.new()
	grid.add_child(_model_input)

	grid.add_child(_make_label("API Key"))
	_api_key_input = LineEdit.new()
	_api_key_input.secret = true
	grid.add_child(_api_key_input)

	grid.add_child(_make_label("Timeout (sec)"))
	_timeout_input = SpinBox.new()
	_timeout_input.min_value = 5
	_timeout_input.max_value = 300
	_timeout_input.step = 1
	grid.add_child(_timeout_input)

	grid.add_child(_make_label("Max Context Records"))
	_max_context_input = SpinBox.new()
	_max_context_input.min_value = 6
	_max_context_input.max_value = 200
	_max_context_input.step = 1
	grid.add_child(_max_context_input)

	var button_row := HBoxContainer.new()
	root.add_child(button_row)

	var save_button := Button.new()
	save_button.text = "保存设置"
	save_button.pressed.connect(_on_save_pressed)
	button_row.add_child(save_button)

	var test_button := Button.new()
	test_button.text = "测试连接"
	test_button.pressed.connect(_on_test_connection_pressed)
	button_row.add_child(test_button)

	root.add_child(_make_label("最近一次测试结果"))
	_test_result_output = TextEdit.new()
	_test_result_output.custom_minimum_size = Vector2(0, 110)
	_test_result_output.editable = false
	root.add_child(_test_result_output)

	_status_label = Label.new()
	root.add_child(_status_label)


func _load_settings() -> void:
	_base_url_input.text = AI_SETTINGS.get_base_url(editor_plugin)
	_model_input.text = AI_SETTINGS.get_model(editor_plugin)
	_api_key_input.text = AI_SETTINGS.get_api_key(editor_plugin)
	_timeout_input.value = AI_SETTINGS.get_timeout_sec(editor_plugin)
	_max_context_input.value = AI_SETTINGS.get_max_context_records(editor_plugin)
	_render_test_result()
	_set_status("已加载当前 AI 配置")


func _on_save_pressed() -> void:
	if editor_plugin == null:
		_set_status("缺少 editor_plugin，无法保存到 EditorSettings")
		return
	var saved := AI_SETTINGS.set_provider_config(editor_plugin, {
		"base_url": _base_url_input.text.strip_edges(),
		"model": _model_input.text.strip_edges(),
		"api_key": _api_key_input.text.strip_edges(),
		"timeout_sec": int(_timeout_input.value),
		"max_context_records": int(_max_context_input.value)
	})
	_set_status("AI 设置已保存" if saved else "保存 AI 设置失败")


func _on_test_connection_pressed() -> void:
	var config := {
		"base_url": _base_url_input.text.strip_edges(),
		"model": _model_input.text.strip_edges(),
		"api_key": _api_key_input.text.strip_edges(),
		"timeout_sec": int(_timeout_input.value)
	}
	_set_status("正在测试连接...")
	var result: Dictionary = await _provider.test_connection(config)
	_last_test_meta = {
		"tested_at": Time.get_datetime_string_from_system(false, true),
		"base_url": str(config.get("base_url", "")),
		"model": str(config.get("model", "")),
		"ok": bool(result.get("ok", false)),
		"message": str(result.get("error", "连接测试成功"))
	}
	_render_test_result()
	if bool(result.get("ok", false)):
		_set_status("连接测试成功")
	else:
		_set_status(str(result.get("error", "连接测试失败")))


func _make_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label


func _set_status(message: String) -> void:
	if _status_label:
		_status_label.text = message


func _render_test_result() -> void:
	if _test_result_output == null:
		return
	if _last_test_meta.is_empty():
		_test_result_output.text = "尚未进行连接测试"
		return
	_test_result_output.text = "\n".join([
		"最后测试时间: %s" % str(_last_test_meta.get("tested_at", "-")),
		"Base URL: %s" % str(_last_test_meta.get("base_url", "-")),
		"Model: %s" % str(_last_test_meta.get("model", "-")),
		"状态: %s" % ("成功" if bool(_last_test_meta.get("ok", false)) else "失败"),
		"结果: %s" % str(_last_test_meta.get("message", "-"))
	])
