@tool
extends VBoxContainer
## GameplayTagsDock - Editor UI for tag registry management and query preview.

const DEFAULT_CONFIG_PATH: String = "res://addons/gameplay_tags/config/gameplay_tags.ini"
const CONTENT_MINIMUM_SIZE: Vector2 = Vector2(720, 460)

var _manager: Node = null
var _selected_tag: StringName = StringName()

var _status_label: Label = null
var _path_edit: LineEdit = null
var _search_edit: LineEdit = null
var _tag_tree: Tree = null
var _container_input: LineEdit = null
var _query_input: TextEdit = null
var _query_result_label: Label = null

var _add_dialog: ConfirmationDialog = null
var _add_dialog_input: LineEdit = null
var _remove_dialog: ConfirmationDialog = null
var _rename_dialog: ConfirmationDialog = null
var _rename_dialog_input: LineEdit = null

func _ready() -> void:
	_build_ui()
	if _manager == null:
		set_manager(_resolve_manager())
	_refresh_all()

func set_manager(manager: Node) -> void:
	if _manager and _manager.has_signal("registry_changed"):
		var changed_callable: Callable = Callable(self, "_on_registry_changed")
		if _manager.is_connected("registry_changed", changed_callable):
			_manager.disconnect("registry_changed", changed_callable)

	if _manager and _manager.has_signal("registry_reloaded"):
		var reloaded_callable: Callable = Callable(self, "_on_registry_reloaded")
		if _manager.is_connected("registry_reloaded", reloaded_callable):
			_manager.disconnect("registry_reloaded", reloaded_callable)

	_manager = manager

	if _manager and _manager.has_signal("registry_changed"):
		_manager.connect("registry_changed", Callable(self, "_on_registry_changed"))
	if _manager and _manager.has_signal("registry_reloaded"):
		_manager.connect("registry_reloaded", Callable(self, "_on_registry_reloaded"))

	_refresh_all()

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	custom_minimum_size = CONTENT_MINIMUM_SIZE

	var header_panel := VBoxContainer.new()
	header_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(header_panel)

	var title_label: Label = Label.new()
	title_label.text = "Gameplay Tags"
	header_panel.add_child(title_label)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.text = "Ready."
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_panel.add_child(_status_label)

	var path_row: HBoxContainer = HBoxContainer.new()
	path_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_panel.add_child(path_row)

	var path_label: Label = Label.new()
	path_label.text = "Config"
	path_row.add_child(path_label)

	_path_edit = LineEdit.new()
	_path_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_path_edit.placeholder_text = DEFAULT_CONFIG_PATH
	path_row.add_child(_path_edit)

	var reload_button: Button = Button.new()
	reload_button.text = "Reload"
	reload_button.pressed.connect(_on_reload_pressed)
	path_row.add_child(reload_button)

	var save_button: Button = Button.new()
	save_button.text = "Save"
	save_button.pressed.connect(_on_save_pressed)
	path_row.add_child(save_button)

	var tools_row: HBoxContainer = HBoxContainer.new()
	tools_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_panel.add_child(tools_row)

	_search_edit = LineEdit.new()
	_search_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search_edit.placeholder_text = "Search tags..."
	_search_edit.text_changed.connect(_on_search_changed)
	tools_row.add_child(_search_edit)

	var add_button: Button = Button.new()
	add_button.text = "Add"
	add_button.pressed.connect(_on_add_pressed)
	tools_row.add_child(add_button)

	var rename_button: Button = Button.new()
	rename_button.text = "Rename"
	rename_button.pressed.connect(_on_rename_pressed)
	tools_row.add_child(rename_button)

	var remove_button: Button = Button.new()
	remove_button.text = "Remove"
	remove_button.pressed.connect(_on_remove_pressed)
	tools_row.add_child(remove_button)

	var content_scroll := ScrollContainer.new()
	content_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_scroll.follow_focus = true
	add_child(content_scroll)

	var content_root := MarginContainer.new()
	content_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_root.add_theme_constant_override("margin_left", 4)
	content_root.add_theme_constant_override("margin_right", 4)
	content_root.add_theme_constant_override("margin_top", 4)
	content_root.add_theme_constant_override("margin_bottom", 4)
	content_scroll.add_child(content_root)

	var split: HSplitContainer = HSplitContainer.new()
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.custom_minimum_size = Vector2(0, 320)
	content_root.add_child(split)

	_tag_tree = Tree.new()
	_tag_tree.hide_root = true
	_tag_tree.columns = 1
	_tag_tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tag_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tag_tree.custom_minimum_size = Vector2(220, 280)
	_tag_tree.item_selected.connect(_on_tree_item_selected)
	split.add_child(_tag_tree)

	var query_panel: VBoxContainer = VBoxContainer.new()
	query_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	query_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	query_panel.custom_minimum_size = Vector2(280, 280)
	split.add_child(query_panel)

	var query_title: Label = Label.new()
	query_title.text = "Query Preview"
	query_panel.add_child(query_title)

	var container_label: Label = Label.new()
	container_label.text = "Container Tags (comma-separated)"
	query_panel.add_child(container_label)

	_container_input = LineEdit.new()
	_container_input.placeholder_text = "State.Combat, Status.Burning"
	query_panel.add_child(_container_input)

	var query_label: Label = Label.new()
	query_label.text = "Query JSON (Dictionary)"
	query_panel.add_child(query_label)

	_query_input = TextEdit.new()
	_query_input.custom_minimum_size = Vector2(0, 140)
	_query_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_query_input.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_query_input.text = "{\n  \"type\": \"all_tags\",\n  \"tags\": [\"State.Combat\"],\n  \"expressions\": []\n}"
	query_panel.add_child(_query_input)

	var evaluate_button: Button = Button.new()
	evaluate_button.text = "Evaluate Query"
	evaluate_button.pressed.connect(_on_evaluate_query_pressed)
	query_panel.add_child(evaluate_button)

	_query_result_label = Label.new()
	_query_result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_query_result_label.text = "Result: -"
	query_panel.add_child(_query_result_label)

	_build_dialogs()

func _build_dialogs() -> void:
	_add_dialog = ConfirmationDialog.new()
	_add_dialog.title = "Add Gameplay Tag"
	_add_dialog.confirmed.connect(_on_add_dialog_confirmed)
	add_child(_add_dialog)

	var add_vbox: VBoxContainer = VBoxContainer.new()
	_add_dialog.add_child(add_vbox)
	var add_prompt: Label = Label.new()
	add_prompt.text = "Tag Name"
	add_vbox.add_child(add_prompt)
	_add_dialog_input = LineEdit.new()
	_add_dialog_input.placeholder_text = "Status.Burning"
	add_vbox.add_child(_add_dialog_input)

	_rename_dialog = ConfirmationDialog.new()
	_rename_dialog.title = "Rename Gameplay Tag"
	_rename_dialog.confirmed.connect(_on_rename_dialog_confirmed)
	add_child(_rename_dialog)

	var rename_vbox: VBoxContainer = VBoxContainer.new()
	_rename_dialog.add_child(rename_vbox)
	var rename_prompt: Label = Label.new()
	rename_prompt.text = "New Tag Name"
	rename_vbox.add_child(rename_prompt)
	_rename_dialog_input = LineEdit.new()
	rename_vbox.add_child(_rename_dialog_input)

	_remove_dialog = ConfirmationDialog.new()
	_remove_dialog.title = "Remove Gameplay Tag"
	_remove_dialog.confirmed.connect(_on_remove_dialog_confirmed)
	add_child(_remove_dialog)

func _refresh_all() -> void:
	if _path_edit == null:
		return
	if _manager and _manager.has_method("get_loaded_config_path"):
		_path_edit.text = str(_manager.call("get_loaded_config_path"))
	elif _path_edit.text.is_empty():
		_path_edit.text = DEFAULT_CONFIG_PATH
	_refresh_tree()
	_refresh_status()

func _refresh_tree() -> void:
	if _tag_tree == null:
		return
	_tag_tree.clear()
	var root: TreeItem = _tag_tree.create_item()

	if _manager == null or not _manager.has_method("get_explicit_tags"):
		return

	var explicit_tags: Array = _manager.call("get_explicit_tags")
	var explicit_lookup: Dictionary = {}
	var sorted_tags: Array[String] = []
	for tag_name in explicit_tags:
		var tag_text: String = String(tag_name)
		sorted_tags.append(tag_text)
		explicit_lookup[tag_text] = true
	sorted_tags.sort()

	var filter_text: String = _search_edit.text.strip_edges().to_lower() if _search_edit else ""
	var node_by_path: Dictionary = {}
	for tag_text in sorted_tags:
		if not filter_text.is_empty() and not tag_text.to_lower().contains(filter_text):
			continue

		var segments: PackedStringArray = tag_text.split(".", false)
		var parent_item: TreeItem = root
		var prefix: String = ""
		for segment in segments:
			prefix = segment if prefix.is_empty() else "%s.%s" % [prefix, segment]
			if not node_by_path.has(prefix):
				var item: TreeItem = _tag_tree.create_item(parent_item)
				item.set_text(0, segment)
				item.set_metadata(0, prefix)
				node_by_path[prefix] = item
			parent_item = node_by_path[prefix]

	for node_path in node_by_path.keys():
		var item_to_style: TreeItem = node_by_path[node_path]
		var is_explicit: bool = explicit_lookup.has(node_path)
		if not is_explicit:
			item_to_style.set_custom_color(0, Color(0.6, 0.6, 0.6))
			item_to_style.set_tooltip_text(0, "Implicit parent tag generated from children.")
		else:
			item_to_style.set_tooltip_text(0, "Explicit tag")

func _refresh_status() -> void:
	if _status_label == null:
		return
	if _manager == null:
		_status_label.text = "GameplayTags autoload not found."
		return

	var explicit_count: int = 0
	var all_count: int = 0
	var warning_count: int = 0
	var last_error: String = ""

	if _manager.has_method("get_explicit_tags"):
		explicit_count = (_manager.call("get_explicit_tags") as Array).size()
	if _manager.has_method("get_all_tags"):
		all_count = (_manager.call("get_all_tags") as Array).size()
	if _manager.has_method("get_parse_warnings"):
		warning_count = (_manager.call("get_parse_warnings") as Array).size()
	if _manager.has_method("get_last_error"):
		last_error = str(_manager.call("get_last_error"))

	var status_text: String = "Explicit: %d | All: %d | Warnings: %d" % [explicit_count, all_count, warning_count]
	if not last_error.is_empty():
		status_text += " | Last Error: %s" % last_error
	_status_label.text = status_text

func _on_reload_pressed() -> void:
	if _manager == null or not _manager.has_method("reload_tags"):
		_query_result_label.text = "Result: GameplayTags manager is unavailable."
		return
	var success: bool = bool(_manager.call("reload_tags", _path_edit.text))
	_refresh_all()
	_query_result_label.text = "Result: Reload %s." % ("succeeded" if success else "failed")

func _on_save_pressed() -> void:
	if _manager == null or not _manager.has_method("save_registry"):
		_query_result_label.text = "Result: GameplayTags manager is unavailable."
		return
	var success: bool = bool(_manager.call("save_registry", _path_edit.text))
	_refresh_status()
	_query_result_label.text = "Result: Save %s." % ("succeeded" if success else "failed")

func _on_search_changed(_new_text: String) -> void:
	_refresh_tree()

func _on_tree_item_selected() -> void:
	var selected_item: TreeItem = _tag_tree.get_selected()
	if selected_item == null:
		_selected_tag = StringName()
		return
	_selected_tag = StringName(str(selected_item.get_metadata(0)))

func _on_add_pressed() -> void:
	if _add_dialog == null:
		return
	_add_dialog_input.text = ""
	_add_dialog.popup_centered_ratio(0.3)

func _on_rename_pressed() -> void:
	if String(_selected_tag).is_empty():
		_query_result_label.text = "Result: Select a tag to rename."
		return
	if _rename_dialog == null:
		return
	_rename_dialog_input.text = String(_selected_tag)
	_rename_dialog.popup_centered_ratio(0.3)

func _on_remove_pressed() -> void:
	if String(_selected_tag).is_empty():
		_query_result_label.text = "Result: Select a tag to remove."
		return
	if _remove_dialog == null:
		return
	_remove_dialog.dialog_text = "Remove '%s' and all descendants?" % String(_selected_tag)
	_remove_dialog.popup_centered_ratio(0.3)

func _on_add_dialog_confirmed() -> void:
	if _manager == null or not _manager.has_method("add_explicit_tag"):
		_query_result_label.text = "Result: GameplayTags manager is unavailable."
		return
	var success: bool = bool(_manager.call("add_explicit_tag", _add_dialog_input.text))
	if success:
		_query_result_label.text = "Result: Added tag '%s'." % _add_dialog_input.text.strip_edges()
		_refresh_all()
		return
	_refresh_status()
	_query_result_label.text = "Result: Failed to add tag."

func _on_rename_dialog_confirmed() -> void:
	if _manager == null or not _manager.has_method("rename_tag"):
		_query_result_label.text = "Result: GameplayTags manager is unavailable."
		return
	var success: bool = bool(_manager.call("rename_tag", _selected_tag, _rename_dialog_input.text, true))
	if success:
		_query_result_label.text = "Result: Renamed '%s' -> '%s'." % [String(_selected_tag), _rename_dialog_input.text]
		_selected_tag = StringName(_rename_dialog_input.text.strip_edges())
		_refresh_all()
		return
	_refresh_status()
	_query_result_label.text = "Result: Rename failed."

func _on_remove_dialog_confirmed() -> void:
	if _manager == null or not _manager.has_method("remove_explicit_tag"):
		_query_result_label.text = "Result: GameplayTags manager is unavailable."
		return
	var success: bool = bool(_manager.call("remove_explicit_tag", _selected_tag, true))
	if success:
		_query_result_label.text = "Result: Removed '%s' and descendants." % String(_selected_tag)
		_selected_tag = StringName()
		_refresh_all()
		return
	_refresh_status()
	_query_result_label.text = "Result: Remove failed."

func _on_evaluate_query_pressed() -> void:
	if _manager == null:
		_query_result_label.text = "Result: GameplayTags manager is unavailable."
		return

	var container_tags: Array[StringName] = _parse_csv_tags(_container_input.text)
	var container: GameplayTagContainer = GameplayTagContainer.new()
	for tag_name in container_tags:
		container.add_tag(tag_name)

	var parsed_json: Variant = JSON.parse_string(_query_input.text)
	if not (parsed_json is Dictionary):
		_query_result_label.text = "Result: Query JSON must parse to a Dictionary."
		return

	var query: GameplayTagQuery = GameplayTagQuery.from_dict(parsed_json)
	var result: bool = false
	if _manager.has_method("evaluate_query"):
		result = bool(_manager.call("evaluate_query", container, query))
	else:
		result = query.evaluate(container)

	_query_result_label.text = "Result: %s" % ("MATCH" if result else "NO MATCH")

func _parse_csv_tags(csv_text: String) -> Array[StringName]:
	var result: Array[StringName] = []
	for raw_segment in csv_text.split(",", false):
		var normalized: String = str(raw_segment).strip_edges()
		if normalized.is_empty():
			continue
		result.append(StringName(normalized))
	return result

func _on_registry_changed() -> void:
	_refresh_all()

func _on_registry_reloaded(_tag_count: int, _warning_count: int) -> void:
	_refresh_all()

func _resolve_manager() -> Node:
	if get_tree() == null or get_tree().root == null:
		return null
	return get_tree().root.get_node_or_null("GameplayTags")
