@tool
extends RefCounted
## 编辑器撤销/重做辅助类
## 简化撤销重做操作的创建和管理

var _undo_redo: Object
var _plugin: Object

func _init(plugin: Object):
	_plugin = plugin
	_undo_redo = plugin.get_undo_redo()

## 开始创建撤销/重做动作
func create_action(action_name: String, merge_mode: int = 0) -> Object:
	_undo_redo.create_action(action_name, merge_mode)
	return _undo_redo

## 添加撤销方法调用
func add_undo_method(object: Object, method: StringName, arg1 = null, arg2 = null, arg3 = null):
	if arg1 == null:
		_undo_redo.add_undo_method(object, method)
	elif arg2 == null:
		_undo_redo.add_undo_method(object, method, arg1)
	elif arg3 == null:
		_undo_redo.add_undo_method(object, method, arg1, arg2)
	else:
		_undo_redo.add_undo_method(object, method, arg1, arg2, arg3)

## 添加重做方法调用
func add_redo_method(object: Object, method: StringName, arg1 = null, arg2 = null, arg3 = null):
	if arg1 == null:
		_undo_redo.add_redo_method(object, method)
	elif arg2 == null:
		_undo_redo.add_redo_method(object, method, arg1)
	elif arg3 == null:
		_undo_redo.add_redo_method(object, method, arg1, arg2)
	else:
		_undo_redo.add_redo_method(object, method, arg1, arg2, arg3)

## 添加撤销属性修改
func add_undo_property(object: Object, property: StringName, value: Variant):
	_undo_redo.add_undo_property(object, property, value)

## 添加重做属性修改
func add_redo_property(object: Object, property: StringName, value: Variant):
	_undo_redo.add_redo_property(object, property, value)

## 提交动作
func commit_action():
	_undo_redo.commit_action()

## 快捷方法：创建属性修改的撤销重做
func create_property_action(action_name: String, object: Object, property: StringName, 
		new_value: Variant, old_value: Variant):
	create_action(action_name)
	add_undo_property(object, property, old_value)
	add_redo_property(object, property, new_value)
	add_undo_method(object, "notify_property_list_changed")
	add_redo_method(object, "notify_property_list_changed")
	commit_action()

## 快捷方法：创建方法调用的撤销重做
func create_method_action(action_name: String, object: Object, method: StringName,
		undo_args: Array = [], redo_args: Array = []):
	create_action(action_name)
	
	# 添加撤销方法
	match undo_args.size():
		0: add_undo_method(object, method)
		1: add_undo_method(object, method, undo_args[0])
		2: add_undo_method(object, method, undo_args[0], undo_args[1])
		3: add_undo_method(object, method, undo_args[0], undo_args[1], undo_args[2])
	
	# 添加重做方法
	match redo_args.size():
		0: add_redo_method(object, method)
		1: add_redo_method(object, method, redo_args[0])
		2: add_redo_method(object, method, redo_args[0], redo_args[1])
		3: add_redo_method(object, method, redo_args[0], redo_args[1], redo_args[2])
	
	commit_action()
