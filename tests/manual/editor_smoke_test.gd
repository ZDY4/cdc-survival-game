extends Control

const DIALOG_EDITOR_PATH := "res://addons/cdc_game_editor/editors/dialog_editor/dialog_editor.gd"
const QUEST_EDITOR_PATH := "res://addons/cdc_game_editor/editors/quest_editor/quest_editor.gd"
const FLOW_GRAPH_BASE_PATH := "res://addons/cdc_game_editor/editors/flow_graph/flow_graph_editor_base.gd"
const FLOW_GRAPH_CANVAS_PATH := "res://addons/cdc_game_editor/editors/flow_graph/flow_graph_canvas.gd"
const FLOW_GRAPH_NODE_PATH := "res://addons/cdc_game_editor/editors/flow_graph/flow_graph_node.gd"

func _ready() -> void:
	_probe_script(FLOW_GRAPH_BASE_PATH)
	_probe_script(FLOW_GRAPH_CANVAS_PATH)
	_probe_script(FLOW_GRAPH_NODE_PATH)
	_probe_script(DIALOG_EDITOR_PATH)
	_probe_script(QUEST_EDITOR_PATH)

	var dialog_result := _instantiate_editor("dialog_editor", DIALOG_EDITOR_PATH, Vector2(0, 0), Vector2(960, 540))
	var quest_result := _instantiate_editor("quest_editor", QUEST_EDITOR_PATH, Vector2(960, 0), Vector2(960, 540))
	if dialog_result and quest_result:
		print("[EditorSmokeTest] dialog_editor and quest_editor instantiated successfully")
		await get_tree().process_frame
		await _simulate_quest_node_selection()
		await _simulate_quest_node_move()
	else:
		push_error("[EditorSmokeTest] editor instantiation failed")

	await get_tree().create_timer(0.5).timeout
	get_tree().quit()

func _probe_script(script_path: String) -> void:
	var script: Variant = load(script_path)
	if script == null:
		push_error("[EditorSmokeTest] Failed to load %s" % script_path)
	else:
		print("[EditorSmokeTest] Loaded %s" % script_path)

func _instantiate_editor(editor_name: String, script_path: String, editor_position: Vector2, editor_size: Vector2) -> bool:
	var script: Variant = load(script_path)
	if script == null:
		push_error("[EditorSmokeTest] Failed to load script for %s (%s)" % [editor_name, script_path])
		return false

	var instance: Variant = script.new()
	if not (instance is Control):
		push_error("[EditorSmokeTest] %s must extend Control" % editor_name)
		return false

	var editor: Control = instance
	editor.name = editor_name
	editor.position = editor_position
	editor.size = editor_size
	editor.set_anchors_preset(Control.PRESET_TOP_LEFT)
	add_child(editor)
	return true

func _simulate_quest_node_move() -> void:
	var quest_editor := get_node_or_null("quest_editor")
	if quest_editor == null:
		return

	var graph_edit: Variant = quest_editor.get("_graph_edit")
	if graph_edit == null:
		return

	for child in graph_edit.get_children():
		if child is GraphNode:
			for _step in range(12):
				child.position_offset += Vector2(12, 6)
				await get_tree().process_frame
			print("[EditorSmokeTest] Simulated quest node drag: %s" % child.name)
			return

func _simulate_quest_node_selection() -> void:
	var quest_editor := get_node_or_null("quest_editor")
	if quest_editor == null:
		return

	var node_ids: Variant = quest_editor.get("nodes").keys()
	if not (node_ids is Array) or node_ids.is_empty():
		return

	var first_id := str(node_ids[0])
	if quest_editor.has_method("focus_record"):
		var focused: bool = bool(quest_editor.call("focus_record", first_id))
		await get_tree().process_frame
		await get_tree().process_frame
		print("[EditorSmokeTest] Simulated quest node selection: %s (%s)" % [first_id, focused])
