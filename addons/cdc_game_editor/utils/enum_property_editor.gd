@tool
extends "res://addons/cdc_game_editor/utils/property_editor_base.gd"

## 枚举属性编辑器

var _option_button: OptionButton
var _enum_values: Dictionary = {}  # value -> display_name

@export var enum_values: Dictionary = {}:
	get: return _enum_values
	set(v):
		_enum_values = v
		_update_options()

func _setup_ui():
	# 标签
	if not property_label.is_empty():
		add_child(_create_label(property_label))
	
	# 下拉选择
	_option_button = OptionButton.new()
	_option_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_option_button.item_selected.connect(_on_item_selected)
	_option_button.focus_entered.connect(_start_edit)
	_option_button.focus_exited.connect(_finish_edit)
	add_child(_option_button)
	
	_update_options()

func _update_options():
	if not _option_button:
		return
	
	_option_button.clear()
	
	var index = 0
	for value in _enum_values:
		var display_name = _enum_values[value]
		_option_button.add_item(display_name, index)
		_option_button.set_item_metadata(index, value)
		index += 1

func _update_ui():
	if not _option_button:
		return
	
	# 查找当前值对应的索引
	for i in range(_option_button.item_count):
		if _option_button.get_item_metadata(i) == _current_value:
			_option_button.selected = i
			return
	_option_button.selected = -1

func _on_item_selected(index: int):
	if _is_syncing_ui:
		return
	_current_value = _option_button.get_item_metadata(index)
	
	if not _is_editing:
		value_changed.emit(property_name, _current_value, _old_value)
	else:
		_finish_edit()

func get_value() -> String:
	return str(_current_value) if _current_value != null else ""
