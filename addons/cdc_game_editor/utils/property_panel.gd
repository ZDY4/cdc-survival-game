@tool
extends ScrollContainer
## 属性面板管理器
## 用于动态管理多个属性编辑器

signal property_changed(property_name: String, new_value: Variant, old_value: Variant)
signal edit_started(property_name: String)
signal edit_finished(property_name: String)

var _editors: Dictionary = {}  # property_name -> editor
var _container: VBoxContainer
var _title_label: Label

@export var panel_title: String = "属性":
	get: return _title_label.text if _title_label else ""
	set(v):
		if _title_label:
			_title_label.text = v

func _ready():
	_setup_ui()

func _setup_ui():
	_container = VBoxContainer.new()
	_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_container.add_theme_constant_override("separation", 8)
	add_child(_container)
	
	# 标题
	_title_label = Label.new()
	_title_label.text = panel_title
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 16)
	_title_label.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
	_container.add_child(_title_label)
	
	_container.add_child(HSeparator.new())

## 清除所有编辑器
func clear():
	for name in _editors:
		var editor: Control = _editors[name]
		if editor:
			editor.queue_free()
	_editors.clear()
	
	# Keep title and the first separator, clear all dynamic controls.
	while _container and _container.get_child_count() > 2:
		var child: Node = _container.get_child(_container.get_child_count() - 1)
		_container.remove_child(child)
		child.queue_free()

## 添加字符串属性
func add_string_property(name: String, label: String, value: String = "", 
		multiline: bool = false, placeholder: String = "") -> Control:
	
	var editor = preload("res://addons/cdc_game_editor/utils/string_property_editor.gd").new()
	editor.property_name = name
	editor.property_label = label
	editor.multiline = multiline
	editor.placeholder = placeholder
	editor.set_value(value)
	
	_connect_editor_signals(editor)
	
	_editors[name] = editor
	_container.add_child(editor)
	
	return editor

## 添加数值属性
func add_number_property(name: String, label: String, value: float = 0.0,
		min_val: float = 0.0, max_val: float = 999999.0, step: float = 1.0,
		allow_float: bool = false) -> Control:
	
	var editor = preload("res://addons/cdc_game_editor/utils/number_property_editor.gd").new()
	editor.property_name = name
	editor.property_label = label
	editor.min_value = min_val
	editor.max_value = max_val
	editor.step = step
	editor.allow_float = allow_float
	editor.set_value(value)
	
	_connect_editor_signals(editor)
	
	_editors[name] = editor
	_container.add_child(editor)
	
	return editor

## 添加枚举属性
func add_enum_property(name: String, label: String, enum_values: Dictionary,
		current_value: String = "") -> Control:
	
	var editor = preload("res://addons/cdc_game_editor/utils/enum_property_editor.gd").new()
	editor.property_name = name
	editor.property_label = label
	editor.enum_values = enum_values
	editor.set_value(current_value)
	
	_connect_editor_signals(editor)
	
	_editors[name] = editor
	_container.add_child(editor)
	
	return editor

## 添加只读标签
func add_readonly_label(name: String, label: String, value: String):
	var hbox = HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var lbl = Label.new()
	lbl.text = label
	lbl.custom_minimum_size = Vector2(100, 0)
	hbox.add_child(lbl)
	
	var value_lbl = Label.new()
	value_lbl.text = value
	value_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	hbox.add_child(value_lbl)
	
	_container.add_child(hbox)

## 添加分隔线
func add_separator():
	_container.add_child(HSeparator.new())

## 添加自定义控件
func add_custom_control(control: Control):
	_container.add_child(control)

## 连接编辑器信号
func _connect_editor_signals(editor: Control):
	editor.value_changed.connect(_on_editor_value_changed)
	editor.edit_started.connect(_on_editor_edit_started)
	editor.edit_finished.connect(_on_editor_edit_finished)

## 获取属性编辑器
func get_editor(property_name: String) -> Control:
	return _editors.get(property_name)

## 获取属性值
func get_value(property_name: String) -> Variant:
	var editor = _editors.get(property_name)
	if editor:
		return editor.get_value()
	return null

## 设置属性值
func set_value(property_name: String, value: Variant):
	var editor = _editors.get(property_name)
	if editor:
		editor.set_value(value)

## 添加分段标签
func add_section_label(text: String):
	var label = Label.new()
	label.text = text
	label.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
	label.add_theme_font_size_override("font_size", 14)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_container.add_child(label)

## 信号转发
func _on_editor_value_changed(name: String, new_val: Variant, old_val: Variant):
	property_changed.emit(name, new_val, old_val)

func _on_editor_edit_started(name: String):
	edit_started.emit(name)

func _on_editor_edit_finished(name: String):
	edit_finished.emit(name)
