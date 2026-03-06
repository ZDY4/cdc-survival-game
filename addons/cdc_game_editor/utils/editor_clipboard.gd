@tool
extends RefCounted
## 编辑器剪贴板管理
## 用于节点复制粘贴功能

static var _instance = null

var _clipboard_data: Dictionary = {}
var _clipboard_type: String = ""

static func get_instance() -> RefCounted:
	if _instance == null:
		_instance = load("res://addons/cdc_game_editor/utils/editor_clipboard.gd").new()
	return _instance

## 复制节点数据
func copy_node(node_data: Dictionary, node_type: String):
	_clipboard_data = node_data.duplicate(true)
	_clipboard_type = node_type
	print("节点已 %s" % node_data.get("id", "unknown"))

## 粘贴节点数据
func paste_node() -> Dictionary:
	if _clipboard_data.is_empty():
		return {}
	
	# 创建数据的深拷贝，并生成新ID
	var pasted_data = _clipboard_data.duplicate(true)
	pasted_data.id = _generate_new_id()
	
	# 清除连接信息（因为连接不能自动复制）
	if pasted_data.has("next"):
		pasted_data.next = ""
	if pasted_data.has("true_next"):
		pasted_data.true_next = ""
	if pasted_data.has("false_next"):
		pasted_data.false_next = ""
	
	# 偏移位置（粘贴时稍微偏移
	if pasted_data.has("position"):
		pasted_data.position += Vector2(50, 50)
	
	return pasted_data

## 查剪贴板有数
func has_data() -> bool:
	return not _clipboard_data.is_empty()

## 获取板数
func get_clipboard_type() -> String:
	return _clipboard_type

## 清空
func clear():
	_clipboard_data.clear()
	_clipboard_type = ""

## 生成新ID
func _generate_new_id() -> String:
	return "node_%d" % Time.get_ticks_msec()

## 批量复制
func copy_nodes(nodes: Array[Dictionary], node_type: String):
	_clipboard_data = {
		"is_batch": true,
		"nodes": nodes.duplicate(true),
		"type": node_type
	}
	print("Copied %d nodes" % nodes.size())

## 批量粘贴
func paste_nodes() -> Array[Dictionary]:
	if not _clipboard_data.has("is_batch"):
		var single = paste_node()
		return [single] if not single.is_empty() else []
	
	var pasted_nodes: Array[Dictionary] = []
	var original_nodes: Array = _clipboard_data.nodes
	
	# 创建ID映射原ID -> 新ID
	var id_mapping = {}
	for node in original_nodes:
		id_mapping[node.id] = _generate_new_id()
	
	# 复制节点并更新ID和连
	for node in original_nodes:
		var new_node = node.duplicate(true)
		new_node.id = id_mapping[node.id]
		
		# 更新连接
		if new_node.has("next") and id_mapping.has(new_node.next):
			new_node.next = id_mapping[new_node.next]
		if new_node.has("true_next") and id_mapping.has(new_node.true_next):
			new_node.true_next = id_mapping[new_node.true_next]
		if new_node.has("false_next") and id_mapping.has(new_node.false_next):
			new_node.false_next = id_mapping[new_node.false_next]
		
		# 偏移位置
		if new_node.has("position"):
			new_node.position += Vector2(50, 50)
		
		pasted_nodes.append(new_node)
	
	return pasted_nodes
