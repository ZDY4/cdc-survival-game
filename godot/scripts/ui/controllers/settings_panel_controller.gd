extends Control

var settings_state: Dictionary = {
	"master_volume": 100,
	"music_volume": 100,
	"sfx_volume": 100,
	"window_mode": "windowed",
	"resolution": "1280x720",
	"vsync": true,
	"ui_scale": 100,
	"keybinding_profile": "default",
}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_layout()


func settings_snapshot() -> Dictionary:
	return settings_state.duplicate(true)


func _build_layout() -> void:
	if get_node_or_null("SettingsPanel") != null:
		return

	var panel := PanelContainer.new()
	panel.name = "SettingsPanel"
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left = -430
	panel.offset_right = -16
	panel.offset_top = 224
	panel.offset_bottom = 612
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)

	var box := VBoxContainer.new()
	box.name = "SettingsLines"
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)

	box.add_child(_settings_label("TitleLine", "设置"))
	box.add_child(_settings_label("AudioLine", ""))
	box.add_child(_settings_slider_row("MasterVolume", "主音量", int(settings_state.get("master_volume", 100)), func(value: float) -> void:
		settings_state["master_volume"] = int(roundf(value))
		_refresh_settings_panel_texts()
	))
	box.add_child(_settings_slider_row("MusicVolume", "音乐", int(settings_state.get("music_volume", 100)), func(value: float) -> void:
		settings_state["music_volume"] = int(roundf(value))
		_refresh_settings_panel_texts()
	))
	box.add_child(_settings_slider_row("SfxVolume", "音效", int(settings_state.get("sfx_volume", 100)), func(value: float) -> void:
		settings_state["sfx_volume"] = int(roundf(value))
		_refresh_settings_panel_texts()
	))
	box.add_child(_settings_label("DisplayLine", ""))
	box.add_child(_settings_option_row("WindowMode", "窗口", _settings_window_modes(), str(settings_state.get("window_mode", "windowed")), func(option_id: String) -> void:
		settings_state["window_mode"] = option_id
		_refresh_settings_panel_texts()
	))
	box.add_child(_settings_option_row("Resolution", "分辨率", _settings_resolutions(), str(settings_state.get("resolution", "1280x720")), func(option_id: String) -> void:
		settings_state["resolution"] = option_id
		_refresh_settings_panel_texts()
	))
	box.add_child(_settings_checkbox_row("VSync", "VSync", bool(settings_state.get("vsync", true)), func(enabled: bool) -> void:
		settings_state["vsync"] = enabled
		_refresh_settings_panel_texts()
	))
	box.add_child(_settings_slider_row("UIScale", "UI", int(settings_state.get("ui_scale", 100)), func(value: float) -> void:
		settings_state["ui_scale"] = int(roundf(value))
		_refresh_settings_panel_texts()
	, 75, 150, 5))
	box.add_child(_settings_keybinding_row())
	box.add_child(_settings_label("ControlsLine", ""))
	box.add_child(_settings_label("SettingsFeedbackLine", ""))
	_refresh_settings_panel_texts()


func _settings_slider_row(node_prefix: String, label_text: String, value: int, callback: Callable, min_value: int = 0, max_value: int = 100, step: int = 1) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "%sRow" % node_prefix
	row.custom_minimum_size = Vector2(380, 28)
	row.add_theme_constant_override("separation", 8)
	var label := _settings_label("%sLabel" % node_prefix, label_text)
	label.custom_minimum_size = Vector2(64, 24)
	var slider := HSlider.new()
	slider.name = "%sSlider" % node_prefix
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.value = clampi(value, min_value, max_value)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.tooltip_text = "%s %d%%" % [label_text, int(slider.value)]
	slider.value_changed.connect(callback, CONNECT_DEFERRED)
	row.add_child(label)
	row.add_child(slider)
	return row


func _settings_option_row(node_prefix: String, label_text: String, options: Array[Dictionary], selected_id: String, callback: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "%sRow" % node_prefix
	row.custom_minimum_size = Vector2(380, 30)
	row.add_theme_constant_override("separation", 8)
	var label := _settings_label("%sLabel" % node_prefix, label_text)
	label.custom_minimum_size = Vector2(64, 24)
	var option := OptionButton.new()
	option.name = "%sOption" % node_prefix
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var selected_index := 0
	for i in range(options.size()):
		var option_data: Dictionary = _dictionary_or_empty(options[i])
		option.add_item(str(option_data.get("label", option_data.get("id", ""))))
		option.set_item_metadata(i, str(option_data.get("id", "")))
		if str(option_data.get("id", "")) == selected_id:
			selected_index = i
	option.select(selected_index)
	option.item_selected.connect(func(index: int) -> void:
		callback.call(str(option.get_item_metadata(index)))
	, CONNECT_DEFERRED)
	row.add_child(label)
	row.add_child(option)
	return row


func _settings_checkbox_row(node_prefix: String, label_text: String, enabled: bool, callback: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "%sRow" % node_prefix
	row.custom_minimum_size = Vector2(380, 28)
	var checkbox := CheckBox.new()
	checkbox.name = "%sCheckBox" % node_prefix
	checkbox.text = label_text
	checkbox.button_pressed = enabled
	checkbox.tooltip_text = "切换 %s" % label_text
	checkbox.toggled.connect(callback, CONNECT_DEFERRED)
	row.add_child(checkbox)
	return row


func _settings_keybinding_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "KeybindingRow"
	row.custom_minimum_size = Vector2(380, 30)
	row.add_theme_constant_override("separation", 8)
	var label := _settings_label("KeybindingLabel", "按键")
	label.custom_minimum_size = Vector2(64, 24)
	var button := Button.new()
	button.name = "KeybindingCycleButton"
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_NONE
	button.tooltip_text = "切换按键方案"
	button.pressed.connect(func() -> void:
		settings_state["keybinding_profile"] = _next_keybinding_profile(str(settings_state.get("keybinding_profile", "default")))
		_refresh_settings_panel_texts()
	, CONNECT_DEFERRED)
	row.add_child(label)
	row.add_child(button)
	return row


func _refresh_settings_panel_texts() -> void:
	var audio := find_child("AudioLine", true, false) as Label
	if audio != null:
		audio.text = "音量: 主音量 %d%% | 音乐 %d%% | 音效 %d%%" % [
			int(settings_state.get("master_volume", 100)),
			int(settings_state.get("music_volume", 100)),
			int(settings_state.get("sfx_volume", 100)),
		]
	var display := find_child("DisplayLine", true, false) as Label
	if display != null:
		display.text = "显示: %s | %s | VSync %s | UI %d%%" % [
			_settings_option_label(_settings_window_modes(), str(settings_state.get("window_mode", "windowed"))),
			str(settings_state.get("resolution", "1280x720")),
			"开启" if bool(settings_state.get("vsync", true)) else "关闭",
			int(settings_state.get("ui_scale", 100)),
		]
	var controls := find_child("ControlsLine", true, false) as Label
	if controls != null:
		controls.text = "按键方案: %s | Esc 关闭 | I/C/M/J/K/L 面板 | Space 等待" % _settings_option_label(_settings_keybinding_profiles(), str(settings_state.get("keybinding_profile", "default")))
	var feedback := find_child("SettingsFeedbackLine", true, false) as Label
	if feedback != null:
		feedback.text = "设置已更新（当前会话）"
	var key_button := find_child("KeybindingCycleButton", true, false) as Button
	if key_button != null:
		key_button.text = _settings_option_label(_settings_keybinding_profiles(), str(settings_state.get("keybinding_profile", "default")))
	_sync_slider_tooltip("MasterVolume", "主音量")
	_sync_slider_tooltip("MusicVolume", "音乐")
	_sync_slider_tooltip("SfxVolume", "音效")
	_sync_slider_tooltip("UIScale", "UI")


func _sync_slider_tooltip(node_prefix: String, label_text: String) -> void:
	var slider := find_child("%sSlider" % node_prefix, true, false) as HSlider
	if slider != null:
		slider.tooltip_text = "%s %d%%" % [label_text, int(slider.value)]


func _settings_window_modes() -> Array[Dictionary]:
	return [
		{"id": "windowed", "label": "窗口模式"},
		{"id": "fullscreen", "label": "全屏"},
		{"id": "borderless", "label": "无边框"},
	]


func _settings_resolutions() -> Array[Dictionary]:
	return [
		{"id": "1280x720", "label": "1280x720"},
		{"id": "1600x900", "label": "1600x900"},
		{"id": "1920x1080", "label": "1920x1080"},
	]


func _settings_keybinding_profiles() -> Array[Dictionary]:
	return [
		{"id": "default", "label": "默认"},
		{"id": "left_handed", "label": "左手"},
		{"id": "controller", "label": "手柄"},
	]


func _settings_option_label(options: Array[Dictionary], option_id: String) -> String:
	for option in options:
		var data: Dictionary = _dictionary_or_empty(option)
		if str(data.get("id", "")) == option_id:
			return str(data.get("label", option_id))
	return option_id


func _next_keybinding_profile(current_id: String) -> String:
	var profiles := _settings_keybinding_profiles()
	for i in range(profiles.size()):
		if str(_dictionary_or_empty(profiles[i]).get("id", "")) == current_id:
			return str(_dictionary_or_empty(profiles[(i + 1) % profiles.size()]).get("id", "default"))
	return "default"


func _settings_label(node_name: String, text: String) -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = text
	label.clip_text = true
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}
