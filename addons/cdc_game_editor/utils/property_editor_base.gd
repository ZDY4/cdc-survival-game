@tool
extends VBoxContainer
## 属性编辑器基类
## 提供统一的属性编辑功能和信号

signal value_changed(property_name: String, new_value: Variant, old_value: Variant)
signal edit_started(property_name: String)
signal edit_finished(property_name: String)

@export var property_name: String = ""
@export var property_label: String = ""
@export var read_only: bool = false

var _current_value: Variant
var _old_value: Variant
var _is_editing: bool = false

func _ready():
	_setup_ui()
	_update_ui()

## 设置UI（子类重写）
func _setup_ui():
	pass

## 更新UI显示（子类重写）
func _update_ui():
	pass

## 设置值（外部调用）
func set_value(value: Variant, emit_signal: bool = false):
	_old_value = _current_value
	_current_value = value
	_update_ui()
	
	if emit_signal:
		value_changed.emit(property_name, value, _old_value)

## 获取当前值
func get_value() -> Variant:
	return _current_value

## 获取属性名
func get_property_name() -> String:
	return property_name

## 开始编辑
func _start_edit():
	if not _is_editing:
		_is_editing = true
		_old_value = _current_value
		edit_started.emit(property_name)

## 结束编辑
func _finish_edit():
	if _is_editing:
		_is_editing = false
		edit_finished.emit(property_name)
		if _old_value != _current_value:
			value_changed.emit(property_name, _current_value, _old_value)

## 取消编辑（恢复原值）
func cancel_edit():
	if _is_editing:
		_current_value = _old_value
		_is_editing = false
		_update_ui()

## 创建标签
func _create_label(text: String) -> Label:
	var label = Label.new()
	label.text = text if not text.is_empty() else property_label
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label

## 创建分隔线
func _add_separator():
	add_child(HSeparator.new())
