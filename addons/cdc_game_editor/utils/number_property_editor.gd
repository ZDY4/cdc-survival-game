@tool
extends "res://addons/cdc_game_editor/utils/property_editor_base.gd"

## 数值属性编辑器

var _spin_box: SpinBox

@export var min_value: float = 0.0
@export var max_value: float = 100.0
@export var step: float = 1.0
@export var allow_float: bool = false

func _setup_ui():
	# 标签
	if not property_label.is_empty():
		add_child(_create_label(property_label))
	
	# 数值编辑器
	_spin_box = SpinBox.new()
	_spin_box.min_value = min_value
	_spin_box.max_value = max_value
	_spin_box.step = step
	_spin_box.allow_greater = true
	_spin_box.allow_lesser = true
	_spin_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_spin_box.value_changed.connect(_on_value_changed)
	_spin_box.get_line_edit().focus_entered.connect(_start_edit)
	_spin_box.get_line_edit().focus_exited.connect(_finish_edit)
	add_child(_spin_box)

func _update_ui():
	if _spin_box:
		_spin_box.value = float(_current_value) if _current_value != null else 0.0

func _on_value_changed(new_value: float):
	if _is_syncing_ui:
		return
	if allow_float:
		_current_value = new_value
	else:
		_current_value = int(new_value)
	
	if not _is_editing:
		value_changed.emit(property_name, _current_value, _old_value)

func get_value() -> Variant:
	if allow_float:
		return float(_current_value) if _current_value != null else 0.0
	else:
		return int(_current_value) if _current_value != null else 0
