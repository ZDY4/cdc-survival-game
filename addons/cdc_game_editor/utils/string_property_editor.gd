@tool
extends "res://addons/cdc_game_editor/utils/property_editor_base.gd"

## 字符串属性编辑器

var _line_edit: LineEdit
var _text_edit: TextEdit
var _editor_control: Control
var _placeholder: String = ""
var _multiline: bool = false

@export var multiline: bool = false:
	get: return _multiline
	set(v):
		_multiline = v
		if is_node_ready():
			_setup_editor()
			_update_ui()

@export var placeholder: String = "":
	get: return _placeholder
	set(v):
		_placeholder = v
		if _line_edit:
			_line_edit.placeholder_text = v
		if _text_edit:
			_text_edit.placeholder_text = v

func _setup_ui():
	# 标签
	if not property_label.is_empty():
		add_child(_create_label(property_label))
	
	_setup_editor()

func _setup_editor():
	# 移除旧编辑器
	if _editor_control and is_instance_valid(_editor_control):
		_editor_control.queue_free()
	_editor_control = null
	_line_edit = null
	_text_edit = null
	
	if _multiline:
		_text_edit = TextEdit.new()
		_text_edit.custom_minimum_size = Vector2(0, 100)
		_text_edit.placeholder_text = _placeholder
		_text_edit.text_changed.connect(_on_multiline_text_changed)
		_text_edit.focus_entered.connect(_start_edit)
		_text_edit.focus_exited.connect(_finish_edit)
		_editor_control = _text_edit
		add_child(_text_edit)
	else:
		_line_edit = LineEdit.new()
		_line_edit.placeholder_text = _placeholder
		_line_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_line_edit.text_changed.connect(_on_line_text_changed)
		_line_edit.focus_entered.connect(_start_edit)
		_line_edit.focus_exited.connect(_finish_edit)
		_editor_control = _line_edit
		add_child(_line_edit)

func _update_ui():
	if _line_edit:
		_line_edit.text = str(_current_value) if _current_value != null else ""
	elif _text_edit:
		_text_edit.text = str(_current_value) if _current_value != null else ""

func _on_line_text_changed(new_text: String):
	_current_value = new_text
	if not _is_editing:
		value_changed.emit(property_name, _current_value, _old_value)

func _on_multiline_text_changed():
	if not _text_edit:
		return
	_current_value = _text_edit.text
	if not _is_editing:
		value_changed.emit(property_name, _current_value, _old_value)

func get_value() -> String:
	return str(_current_value) if _current_value != null else ""
