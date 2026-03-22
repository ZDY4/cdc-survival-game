extends "res://core/base_module.gd"
# 注意: 作为 Autoload 单例，不使用 class_name
const ShopComponentScript = preload("res://modules/npc/components/shop_component.gd")
const DialogUIScript = preload("res://modules/dialog/dialog_ui.gd")
const DIALOG_DATA_DIR := "res://data/dialogues"

signal dialog_started(text: String, speaker: String)
signal choice_selected(index: int, choice_text: String)
signal dialog_finished()
signal dialog_hidden()

var _dialog_ui: DialogUIScript
var _is_dialog_active: bool = false

func _ready():
	# 延迟加载UI，避免 _ready 时场景树不完整
	call_deferred("_setup_ui")

func _setup_ui():
	# Load dialog UI
	if not FileAccess.file_exists("res://modules/dialog/dialog_ui.tscn"):
		push_error("[DialogModule] dialog_ui.tscn not found!")
		return
	
	var dialog_scene = load("res://modules/dialog/dialog_ui.tscn")
	if not dialog_scene:
		push_error("[DialogModule] Failed to load dialog_ui.tscn")
		return
	
	_dialog_ui = dialog_scene.instantiate()
	if not _dialog_ui:
		push_error("[DialogModule] Failed to instantiate dialog UI")
		return
	
	get_tree().root.add_child(_dialog_ui)
	if _dialog_ui.has_method("hide_dialog"):
		_dialog_ui.hide_dialog()
	_set_dialog_active(false)
	
	# Connect UI signals
	if _dialog_ui.has_signal("text_finished"):
		_dialog_ui.text_finished.connect(_on_text_finished)
	if _dialog_ui.has_signal("choice_made"):
		_dialog_ui.choice_made.connect(_on_choice_made)

func show_dialog(text: String, speaker: String = "", portrait: String = ""):
	if not _validate_input({
		"text": text
	}, ["text"]):
		return
	if not _dialog_ui:
		return
	
	_set_dialog_active(true)
	dialog_started.emit(text, speaker)
	_dialog_ui.show_text(text, speaker, portrait)

func show_choices(choices: Array[String]):
	if not _validate_input({
		"choices": choices
	}, ["choices"]):
		return -1
	if not _dialog_ui:
		return -1
	
	# 注意: 这是一个协程，调用处需要使用 await
	_set_dialog_active(true)
	var selected_index: int = await _dialog_ui.show_choices(choices)
	_set_dialog_active(false)
	dialog_hidden.emit()
	return selected_index

func hide_dialog():
	if not _dialog_ui:
		return
	_dialog_ui.hide_dialog()
	_set_dialog_active(false)
	dialog_hidden.emit()

func is_dialog_active() -> bool:
	return _is_dialog_active

func play_dialog_resource(dialog_id: String, context: Dictionary = {}) -> Dictionary:
	var resolved_dialog_id := dialog_id.strip_edges()
	var fallback_result := {"selected_port": 0, "branch_key": 0}
	if resolved_dialog_id.is_empty():
		return fallback_result
	if not _dialog_ui:
		return fallback_result

	var dialog_data_variant: Variant = _load_dialog_json(resolved_dialog_id)
	if not (dialog_data_variant is Dictionary):
		return fallback_result

	var dialog_data: Dictionary = dialog_data_variant
	var dialog_nodes: Dictionary = {}
	for node_variant in dialog_data.get("nodes", []):
		if not (node_variant is Dictionary):
			continue
		var node_data: Dictionary = node_variant
		dialog_nodes[str(node_data.get("id", ""))] = node_data

	if dialog_nodes.is_empty():
		return fallback_result

	var current_node_id := _find_dialog_start_node(dialog_nodes)
	while not current_node_id.is_empty():
		var node: Dictionary = dialog_nodes.get(current_node_id, {})
		if node.is_empty():
			hide_dialog()
			return fallback_result

		match str(node.get("type", "")):
			"dialog":
				show_dialog(
					str(node.get("text", "...")),
					_resolve_dialog_speaker(node, context),
					_resolve_dialog_portrait(node, context)
				)
				await dialog_finished
				current_node_id = _get_dialog_graph_next(dialog_data, dialog_nodes, current_node_id, 0)
			"choice":
				var visible_choices: Array[Dictionary] = _build_visible_choice_entries(
					dialog_data,
					dialog_nodes,
					current_node_id,
					node,
					context
				)
				if visible_choices.is_empty():
					hide_dialog()
					return fallback_result
				var choice_texts: Array[String] = []
				for entry_variant in visible_choices:
					choice_texts.append(str(entry_variant.get("text", "选项")))
				var selected_visible_index: int = await show_choices(choice_texts)
				if selected_visible_index < 0:
					selected_visible_index = 0
				var selected_index: int = int(visible_choices[selected_visible_index].get("original_index", 0))
				current_node_id = _get_dialog_graph_next(dialog_data, dialog_nodes, current_node_id, selected_index)
				if current_node_id.is_empty():
					return {"selected_port": selected_index, "branch_key": selected_index}
			"action":
				await _execute_dialog_actions(node.get("actions", []), context)
				current_node_id = _get_dialog_graph_next(dialog_data, dialog_nodes, current_node_id, 0)
			"condition":
				var true_target := _get_dialog_graph_next(dialog_data, dialog_nodes, current_node_id, 0)
				var false_target := _get_dialog_graph_next(dialog_data, dialog_nodes, current_node_id, 1)
				current_node_id = true_target if not true_target.is_empty() else false_target
			"end":
				hide_dialog()
				return {
					"selected_port": 0,
					"branch_key": str(node.get("end_type", "end"))
				}
			_:
				current_node_id = _get_dialog_graph_next(dialog_data, dialog_nodes, current_node_id, 0)

	hide_dialog()
	return fallback_result

func _on_text_finished():
	dialog_finished.emit()

func _on_choice_made(index: int, choice_text: String):
	choice_selected.emit(index, choice_text)

func _set_dialog_active(is_active: bool) -> void:
	_is_dialog_active = is_active

func _load_dialog_json(dialog_id: String) -> Variant:
	var path := "%s/%s.json" % [DIALOG_DATA_DIR, dialog_id]
	if not FileAccess.file_exists(path):
		push_warning("[DialogModule] 对话文件不存在: %s" % path)
		return null

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("[DialogModule] 无法打开对话文件: %s" % path)
		return null

	var json_text := file.get_as_text()
	file.close()

	var json := JSON.new()
	if json.parse(json_text) != OK:
		push_warning("[DialogModule] JSON 解析失败: %s" % path)
		return null

	return json.data

func _resolve_dialog_speaker(node: Dictionary, context: Dictionary) -> String:
	var speaker := str(node.get("speaker", "")).strip_edges()
	if not speaker.is_empty():
		return speaker
	return str(context.get("speaker_name", "")).strip_edges()

func _resolve_dialog_portrait(node: Dictionary, context: Dictionary) -> String:
	var portrait := str(node.get("portrait", "")).strip_edges()
	if not portrait.is_empty():
		return portrait
	return str(context.get("portrait_path", "")).strip_edges()

func _execute_dialog_actions(actions: Array, context: Dictionary) -> void:
	for action_variant in actions:
		if not (action_variant is Dictionary):
			continue
		await _execute_dialog_action(action_variant, context)

func _execute_dialog_action(action: Dictionary, context: Dictionary) -> void:
	var action_type := str(action.get("type", "")).strip_edges()
	match action_type:
		"open_trade":
			hide_dialog()
			var trade_component := _resolve_trade_component(context)
			if trade_component == null:
				push_warning("[DialogModule] open_trade 动作缺少交易组件")
				return
			await trade_component.open_trade_ui()
		_:
			push_warning("[DialogModule] 未知对话动作类型: %s" % action_type)

func _build_visible_choice_entries(
	dialog_data: Dictionary,
	dialog_nodes: Dictionary,
	node_id: String,
	choice_node: Dictionary,
	context: Dictionary
) -> Array[Dictionary]:
	var visible_entries: Array[Dictionary] = []
	var options: Array = choice_node.get("options", [])
	for option_index in range(options.size()):
		var option_variant: Variant = options[option_index]
		if not (option_variant is Dictionary):
			continue
		var option_data: Dictionary = option_variant
		if not _should_show_choice_option(dialog_data, dialog_nodes, node_id, option_index, context):
			continue
		visible_entries.append({
			"text": str(option_data.get("text", "选项")),
			"original_index": option_index
		})
	return visible_entries

func _should_show_choice_option(
	dialog_data: Dictionary,
	dialog_nodes: Dictionary,
	node_id: String,
	option_index: int,
	context: Dictionary
) -> bool:
	var next_node_id: String = _get_dialog_graph_next(dialog_data, dialog_nodes, node_id, option_index)
	if next_node_id.is_empty():
		return true

	var next_node: Dictionary = dialog_nodes.get(next_node_id, {})
	if str(next_node.get("type", "")) != "action":
		return true

	for action_variant in next_node.get("actions", []):
		if not (action_variant is Dictionary):
			continue
		var action_data: Dictionary = action_variant
		if str(action_data.get("type", "")).strip_edges() != "open_trade":
			continue
		return _resolve_trade_component(context) != null

	return true

func _resolve_trade_component(context: Dictionary) -> ShopComponentScript:
	var actor := context.get("actor", null) as Node
	if actor != null:
		var bound_component := _get_bound_trade_component(actor)
		if bound_component != null:
			return bound_component
		var trade_component := _find_trade_component(actor)
		if trade_component != null:
			return _validate_trade_component(trade_component)

	var interactable := context.get("interactable", null) as Node
	var node := interactable
	while node != null:
		var bound_component := _get_bound_trade_component(node)
		if bound_component != null:
			return bound_component
		var trade_component := _find_trade_component(node)
		if trade_component != null:
			return _validate_trade_component(trade_component)
		node = node.get_parent()

	return null

func _get_bound_trade_component(node: Node) -> ShopComponentScript:
	var bound_variant: Variant = node.get_meta("bound_trade_component", null)
	if bound_variant is ShopComponentScript:
		return _validate_trade_component(bound_variant as ShopComponentScript)
	return null

func _validate_trade_component(trade_component: ShopComponentScript) -> ShopComponentScript:
	if trade_component == null:
		return null
	if trade_component.has_method("is_trade_available") and not bool(trade_component.call("is_trade_available")):
		return null
	return trade_component

func _find_trade_component(node: Node) -> ShopComponentScript:
	for child in node.get_children():
		if child is ShopComponentScript:
			return child as ShopComponentScript
	return null

func _get_dialog_graph_next(dialog_data: Dictionary, dialog_nodes: Dictionary, from_node_id: String, from_port: int) -> String:
	for conn_variant in dialog_data.get("connections", []):
		if not (conn_variant is Dictionary):
			continue
		var conn: Dictionary = conn_variant
		if str(conn.get("from", "")) != from_node_id:
			continue
		if int(conn.get("from_port", 0)) != from_port:
			continue
		return str(conn.get("to", ""))

	var from_node: Dictionary = dialog_nodes.get(from_node_id, {})
	match str(from_node.get("type", "")):
		"dialog", "action":
			return str(from_node.get("next", ""))
		"choice":
			var options: Array = from_node.get("options", [])
			if from_port >= 0 and from_port < options.size():
				return str(options[from_port].get("next", ""))
		"condition":
			return str(from_node.get("true_next", "")) if from_port == 0 else str(from_node.get("false_next", ""))
	return ""

func _find_dialog_start_node(dialog_nodes: Dictionary) -> String:
	if dialog_nodes.has("start"):
		return "start"
	for node_id_variant in dialog_nodes.keys():
		var node_id := str(node_id_variant)
		var node: Dictionary = dialog_nodes[node_id]
		if bool(node.get("is_start", false)):
			return node_id
	if not dialog_nodes.is_empty():
		return str(dialog_nodes.keys()[0])
	return ""
