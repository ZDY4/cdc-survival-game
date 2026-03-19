@tool
extends VBoxContainer
## GameplayTagsDock - Editor UI for tag registry management and query preview.

const DEFAULT_CONFIG_PATH: String = "res://config/gameplay_tags.ini"
const MANAGER_SCRIPT_PATH: String = "res://addons/gameplay_tags/runtime/gameplay_tags_manager.gd"
const CONTENT_MINIMUM_SIZE: Vector2 = Vector2(860, 560)
const TREE_MENU_COPY_TAG: int = 1
const TREE_MENU_USE_AS_CONTAINER: int = 2
const TREE_MENU_USE_IN_QUERY: int = 3
const TREE_MENU_ADD_CHILD: int = 4
const SEARCHABLE_REFERENCE_EXTENSIONS: PackedStringArray = [
	"gd",
	"tscn",
	"tres",
	"res",
	"json",
	"cfg",
	"ini",
	"txt"
]
const REFERENCE_SCAN_EXCLUDED_PREFIXES: PackedStringArray = [
	"res://.godot/",
	"res://addons/gameplay_tags/"
]
const REFERENCE_SCAN_EXCLUDED_FILES: PackedStringArray = [
	DEFAULT_CONFIG_PATH
]

var _manager: Node = null
var _local_manager: Node = null
var _selected_tag: StringName = StringName()
var _using_local_manager: bool = false
var _dirty: bool = false
var _pending_close_callback: Callable = Callable()

var _status_label: Label = null
var _path_edit: LineEdit = null
var _path_hint_label: Label = null
var _search_edit: LineEdit = null
var _tag_summary_label: Label = null
var _tag_tree: Tree = null
var _selected_tag_label: Label = null
var _selected_kind_label: Label = null
var _selected_parent_label: Label = null
var _validation_label: Label = null
var _warnings_list: ItemList = null
var _reference_summary_label: Label = null
var _reference_list: ItemList = null
var _container_input: LineEdit = null
var _query_input: TextEdit = null
var _query_result_label: Label = null

var _add_dialog: ConfirmationDialog = null
var _add_dialog_input: LineEdit = null
var _remove_dialog: ConfirmationDialog = null
var _rename_dialog: ConfirmationDialog = null
var _rename_dialog_input: LineEdit = null
var _rename_preview_label: Label = null
var _close_confirmation_dialog: ConfirmationDialog = null
var _tree_context_menu: PopupMenu = null

func _ready() -> void:
	_build_ui()
	if _manager == null:
		set_manager(_resolve_manager())
	else:
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
	_using_local_manager = _manager != null and _manager == _local_manager

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
	add_theme_constant_override("separation", 10)

	var root_margin := MarginContainer.new()
	root_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_margin.add_theme_constant_override("margin_left", 12)
	root_margin.add_theme_constant_override("margin_right", 12)
	root_margin.add_theme_constant_override("margin_top", 12)
	root_margin.add_theme_constant_override("margin_bottom", 12)
	add_child(root_margin)

	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 10)
	root_margin.add_child(root)

	var header_panel := PanelContainer.new()
	header_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(header_panel)

	var header_box := VBoxContainer.new()
	header_box.add_theme_constant_override("separation", 8)
	header_panel.add_child(header_box)

	var title_label := Label.new()
	title_label.text = "Gameplay Tags Registry"
	header_box.add_child(title_label)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.text = "Loading registry..."
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_box.add_child(_status_label)

	var path_row := HBoxContainer.new()
	path_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	path_row.add_theme_constant_override("separation", 8)
	header_box.add_child(path_row)

	var path_label := Label.new()
	path_label.text = "Config"
	path_row.add_child(path_label)

	_path_edit = LineEdit.new()
	_path_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_path_edit.placeholder_text = DEFAULT_CONFIG_PATH
	path_row.add_child(_path_edit)

	var reset_button := Button.new()
	reset_button.text = "Default"
	reset_button.tooltip_text = "Reset to the project config path."
	reset_button.pressed.connect(_on_reset_path_pressed)
	path_row.add_child(reset_button)

	var reload_button := Button.new()
	reload_button.text = "Reload"
	reload_button.pressed.connect(_on_reload_pressed)
	path_row.add_child(reload_button)

	var save_button := Button.new()
	save_button.text = "Save"
	save_button.pressed.connect(_on_save_pressed)
	path_row.add_child(save_button)

	_path_hint_label = Label.new()
	_path_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_path_hint_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_box.add_child(_path_hint_label)

	var main_split := HSplitContainer.new()
	main_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_split.split_offset = 420
	root.add_child(main_split)

	var left_panel := PanelContainer.new()
	left_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_split.add_child(left_panel)

	var left_box := VBoxContainer.new()
	left_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_box.add_theme_constant_override("separation", 8)
	left_panel.add_child(left_box)

	var library_title := Label.new()
	library_title.text = "Tag Library"
	var library_header := HBoxContainer.new()
	library_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	library_header.add_theme_constant_override("separation", 8)
	left_box.add_child(library_header)
	library_header.add_child(library_title)

	var expand_button := Button.new()
	expand_button.text = "Expand"
	expand_button.tooltip_text = "Expand all visible tag groups."
	expand_button.pressed.connect(_on_expand_all_pressed)
	library_header.add_child(expand_button)

	var collapse_button := Button.new()
	collapse_button.text = "Collapse"
	collapse_button.tooltip_text = "Collapse all visible tag groups."
	collapse_button.pressed.connect(_on_collapse_all_pressed)
	library_header.add_child(collapse_button)

	var tools_row := HBoxContainer.new()
	tools_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tools_row.add_theme_constant_override("separation", 8)
	left_box.add_child(tools_row)

	_search_edit = LineEdit.new()
	_search_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search_edit.placeholder_text = "Search tags..."
	_search_edit.text_changed.connect(_on_search_changed)
	tools_row.add_child(_search_edit)

	var add_button := Button.new()
	add_button.text = "Add"
	add_button.pressed.connect(_on_add_pressed)
	tools_row.add_child(add_button)

	var add_child_button := Button.new()
	add_child_button.text = "Add Child"
	add_child_button.pressed.connect(_on_add_child_pressed)
	tools_row.add_child(add_child_button)

	var rename_button := Button.new()
	rename_button.text = "Rename"
	rename_button.pressed.connect(_on_rename_pressed)
	tools_row.add_child(rename_button)

	var remove_button := Button.new()
	remove_button.text = "Remove"
	remove_button.pressed.connect(_on_remove_pressed)
	tools_row.add_child(remove_button)

	_tag_summary_label = Label.new()
	_tag_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tag_summary_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_box.add_child(_tag_summary_label)

	_tag_tree = Tree.new()
	_tag_tree.hide_root = true
	_tag_tree.columns = 1
	_tag_tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tag_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tag_tree.custom_minimum_size = Vector2(320, 320)
	_tag_tree.item_selected.connect(_on_tree_item_selected)
	_tag_tree.gui_input.connect(_on_tag_tree_gui_input)
	left_box.add_child(_tag_tree)

	var right_panel := PanelContainer.new()
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_split.add_child(right_panel)

	var right_box := VBoxContainer.new()
	right_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_box.add_theme_constant_override("separation", 10)
	right_panel.add_child(right_box)

	var selection_title := Label.new()
	selection_title.text = "Selected Tag"
	right_box.add_child(selection_title)

	_selected_tag_label = Label.new()
	_selected_tag_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_selected_tag_label.text = "No tag selected."
	right_box.add_child(_selected_tag_label)

	_selected_kind_label = Label.new()
	_selected_kind_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_selected_kind_label.text = "Kind: -"
	right_box.add_child(_selected_kind_label)

	_selected_parent_label = Label.new()
	_selected_parent_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_selected_parent_label.text = "Parents: -"
	right_box.add_child(_selected_parent_label)

	var quick_actions := HBoxContainer.new()
	quick_actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quick_actions.add_theme_constant_override("separation", 8)
	right_box.add_child(quick_actions)

	var use_container_button := Button.new()
	use_container_button.text = "Use As Container"
	use_container_button.tooltip_text = "Copy the selected tag into the container preview field."
	use_container_button.pressed.connect(_on_use_selected_as_container_pressed)
	quick_actions.add_child(use_container_button)

	var use_query_button := Button.new()
	use_query_button.text = "Use In Query"
	use_query_button.tooltip_text = "Build a simple all_tags query using the selected tag."
	use_query_button.pressed.connect(_on_use_selected_in_query_pressed)
	quick_actions.add_child(use_query_button)

	var find_references_button := Button.new()
	find_references_button.text = "Find References"
	find_references_button.tooltip_text = "Scan the project for files referencing the selected tag."
	find_references_button.pressed.connect(_on_find_references_pressed)
	quick_actions.add_child(find_references_button)

	var warnings_panel := PanelContainer.new()
	warnings_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	warnings_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_box.add_child(warnings_panel)

	var warnings_box := VBoxContainer.new()
	warnings_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	warnings_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	warnings_box.add_theme_constant_override("separation", 6)
	warnings_panel.add_child(warnings_box)

	var warnings_title := Label.new()
	warnings_title.text = "Warnings And Validation"
	warnings_box.add_child(warnings_title)

	_validation_label = Label.new()
	_validation_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_validation_label.text = "Validation: pending"
	warnings_box.add_child(_validation_label)

	_warnings_list = ItemList.new()
	_warnings_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_warnings_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_warnings_list.custom_minimum_size = Vector2(0, 120)
	warnings_box.add_child(_warnings_list)

	var references_panel := PanelContainer.new()
	references_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	references_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_box.add_child(references_panel)

	var references_box := VBoxContainer.new()
	references_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	references_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	references_box.add_theme_constant_override("separation", 6)
	references_panel.add_child(references_box)

	var references_title := Label.new()
	references_title.text = "Project References"
	references_box.add_child(references_title)

	_reference_summary_label = Label.new()
	_reference_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_reference_summary_label.text = "References: select a tag and scan the project."
	references_box.add_child(_reference_summary_label)

	_reference_list = ItemList.new()
	_reference_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_reference_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_reference_list.custom_minimum_size = Vector2(0, 120)
	references_box.add_child(_reference_list)

	var query_separator := HSeparator.new()
	right_box.add_child(query_separator)

	var query_title := Label.new()
	query_title.text = "Query Preview"
	right_box.add_child(query_title)

	var container_label := Label.new()
	container_label.text = "Container Tags (comma-separated)"
	right_box.add_child(container_label)

	_container_input = LineEdit.new()
	_container_input.placeholder_text = "State.Combat, Status.Burning"
	right_box.add_child(_container_input)

	var query_label := Label.new()
	query_label.text = "Query JSON (Dictionary)"
	right_box.add_child(query_label)

	_query_input = TextEdit.new()
	_query_input.custom_minimum_size = Vector2(0, 220)
	_query_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_query_input.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_query_input.text = "{\n  \"type\": \"all_tags\",\n  \"tags\": [\"State.Combat\"],\n  \"expressions\": []\n}"
	right_box.add_child(_query_input)

	var evaluate_button := Button.new()
	evaluate_button.text = "Evaluate Query"
	evaluate_button.pressed.connect(_on_evaluate_query_pressed)
	right_box.add_child(evaluate_button)

	_query_result_label = Label.new()
	_query_result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_query_result_label.text = "Result: -"
	right_box.add_child(_query_result_label)

	_build_dialogs()

func _build_dialogs() -> void:
	_add_dialog = ConfirmationDialog.new()
	_add_dialog.title = "Add Gameplay Tag"
	_add_dialog.confirmed.connect(_on_add_dialog_confirmed)
	add_child(_add_dialog)

	var add_vbox := VBoxContainer.new()
	_add_dialog.add_child(add_vbox)
	var add_prompt := Label.new()
	add_prompt.text = "Tag Name"
	add_vbox.add_child(add_prompt)
	_add_dialog_input = LineEdit.new()
	_add_dialog_input.placeholder_text = "Status.Burning"
	add_vbox.add_child(_add_dialog_input)

	_rename_dialog = ConfirmationDialog.new()
	_rename_dialog.title = "Rename Gameplay Tag"
	_rename_dialog.confirmed.connect(_on_rename_dialog_confirmed)
	add_child(_rename_dialog)

	var rename_vbox := VBoxContainer.new()
	_rename_dialog.add_child(rename_vbox)
	var rename_prompt := Label.new()
	rename_prompt.text = "New Tag Name"
	rename_vbox.add_child(rename_prompt)
	_rename_dialog_input = LineEdit.new()
	_rename_dialog_input.text_changed.connect(_on_rename_input_changed)
	rename_vbox.add_child(_rename_dialog_input)
	_rename_preview_label = Label.new()
	_rename_preview_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rename_vbox.add_child(_rename_preview_label)

	_remove_dialog = ConfirmationDialog.new()
	_remove_dialog.title = "Remove Gameplay Tag"
	_remove_dialog.confirmed.connect(_on_remove_dialog_confirmed)
	add_child(_remove_dialog)

	_close_confirmation_dialog = ConfirmationDialog.new()
	_close_confirmation_dialog.title = "Unsaved Gameplay Tags"
	_close_confirmation_dialog.dialog_text = "There are unsaved Gameplay Tags changes."
	_close_confirmation_dialog.confirmed.connect(_on_close_dialog_confirmed)
	_close_confirmation_dialog.canceled.connect(_on_close_dialog_canceled)
	_close_confirmation_dialog.add_button("Discard", true, "discard")
	_close_confirmation_dialog.custom_action.connect(_on_close_dialog_custom_action)
	add_child(_close_confirmation_dialog)

	_tree_context_menu = PopupMenu.new()
	_tree_context_menu.add_item("Copy Tag Name", TREE_MENU_COPY_TAG)
	_tree_context_menu.add_item("Add Child Tag", TREE_MENU_ADD_CHILD)
	_tree_context_menu.add_item("Use As Container", TREE_MENU_USE_AS_CONTAINER)
	_tree_context_menu.add_item("Use In Query", TREE_MENU_USE_IN_QUERY)
	_tree_context_menu.id_pressed.connect(_on_tree_context_menu_id_pressed)
	add_child(_tree_context_menu)

func _refresh_all() -> void:
	if _path_edit == null:
		return

	if _manager and _manager.has_method("get_loaded_config_path"):
		_path_edit.text = str(_manager.call("get_loaded_config_path"))
	elif _path_edit.text.strip_edges().is_empty():
		_path_edit.text = DEFAULT_CONFIG_PATH

	_refresh_path_hint()
	_refresh_tree()
	_refresh_status()
	_refresh_selection_details()
	_refresh_warnings_panel()

func _refresh_tree() -> void:
	if _tag_tree == null:
		return

	_tag_tree.clear()
	var root: TreeItem = _tag_tree.create_item()
	var selected_tag_text: String = String(_selected_tag)

	if _manager == null or not _manager.has_method("get_explicit_tags"):
		_add_placeholder_item(root, "Gameplay Tags manager is unavailable.")
		_selected_tag = StringName()
		_refresh_selection_details()
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
		item_to_style.set_collapsed(false)
		var is_explicit: bool = explicit_lookup.has(node_path)
		if not is_explicit:
			item_to_style.set_custom_color(0, Color(0.72, 0.72, 0.72))
			item_to_style.set_tooltip_text(0, "Implicit parent tag generated from child tags.")
		else:
			item_to_style.set_tooltip_text(0, "Explicit tag saved to the config file.")

	if node_by_path.is_empty():
		_add_placeholder_item(root, "No tags found for the current filter.")
		_selected_tag = StringName()
	else:
		if not selected_tag_text.is_empty() and node_by_path.has(selected_tag_text):
			var selected_item: TreeItem = node_by_path[selected_tag_text]
			selected_item.select(0)
			_selected_tag = StringName(selected_tag_text)
		else:
			_selected_tag = StringName()

	_update_tag_summary(node_by_path.size(), explicit_lookup.size(), filter_text)

func _refresh_status() -> void:
	if _status_label == null:
		return
	if _manager == null:
		_status_label.text = "Gameplay Tags manager is unavailable."
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

	var manager_source: String = "Project autoload"
	if _using_local_manager:
		manager_source = "Editor-local manager"

	var status_text: String = "%s | Explicit: %d | All: %d | Warnings: %d" % [
		manager_source,
		explicit_count,
		all_count,
		warning_count
	]
	if not last_error.is_empty():
		status_text += " | Last Error: %s" % last_error
	if _dirty:
		status_text += " | Unsaved changes"
	_status_label.text = status_text

func _refresh_selection_details() -> void:
	if _selected_tag_label == null:
		return

	if _manager == null:
		_selected_tag_label.text = "No Gameplay Tags manager is available in the editor."
		_selected_kind_label.text = "Kind: -"
		_selected_parent_label.text = "Parents: -"
		_clear_reference_results(true)
		return

	var selected_tag_text: String = String(_selected_tag)
	if selected_tag_text.is_empty():
		_selected_tag_label.text = "No tag selected."
		_selected_kind_label.text = "Kind: -"
		_selected_parent_label.text = "Parents: -"
		_clear_reference_results(true)
		return

	var explicit_lookup: Dictionary = {}
	if _manager.has_method("get_explicit_tags"):
		for explicit_tag in _manager.call("get_explicit_tags"):
			explicit_lookup[String(explicit_tag)] = true

	var parent_text: String = "-"
	if _manager.has_method("get_parents"):
		var parents: Array = _manager.call("get_parents", _selected_tag)
		var parent_names: Array[String] = []
		for parent_tag in parents:
			parent_names.append(String(parent_tag))
		if not parent_names.is_empty():
			parent_text = ", ".join(parent_names)

	_selected_tag_label.text = "Name: %s" % selected_tag_text
	_selected_kind_label.text = "Kind: %s" % ("Explicit" if explicit_lookup.has(selected_tag_text) else "Implicit parent")
	_selected_parent_label.text = "Parents: %s" % parent_text
	_clear_reference_results(false)

func _refresh_warnings_panel() -> void:
	if _validation_label == null or _warnings_list == null:
		return

	var validation_issues: Array[String] = _get_validation_issues()
	if validation_issues.is_empty():
		_validation_label.text = "Validation: registry is ready to save."
	else:
		_validation_label.text = "Validation: %d issue(s) must be fixed before saving." % validation_issues.size()

	_warnings_list.clear()
	for validation_issue in validation_issues:
		_warnings_list.add_item("[Validation] %s" % validation_issue)

	if _manager and _manager.has_method("get_parse_warnings"):
		var parse_warnings: Array = _manager.call("get_parse_warnings")
		for parse_warning in parse_warnings:
			_warnings_list.add_item("[Config] %s" % String(parse_warning))

	if _warnings_list.item_count == 0:
		_warnings_list.add_item("No warnings. The current registry is clean.")

func _clear_reference_results(preserve_prompt: bool = true) -> void:
	if _reference_summary_label == null or _reference_list == null:
		return

	_reference_list.clear()
	if preserve_prompt:
		_reference_summary_label.text = "References: select a tag and scan the project."
	else:
		var selected_tag_text: String = String(_selected_tag)
		if selected_tag_text.is_empty():
			_reference_summary_label.text = "References: select a tag and scan the project."
		else:
			_reference_summary_label.text = "References: ready to scan '%s'." % selected_tag_text

func _refresh_reference_results(tag_text: String, references: Array[String]) -> void:
	if _reference_summary_label == null or _reference_list == null:
		return

	_reference_list.clear()
	if references.is_empty():
		_reference_summary_label.text = "References: no project files currently mention '%s'." % tag_text
		_reference_list.add_item("No references found.")
		return

	_reference_summary_label.text = "References: %d file(s) mention '%s'." % [references.size(), tag_text]
	for reference_path in references:
		_reference_list.add_item(reference_path)

func _set_dirty_state(is_dirty: bool) -> void:
	if _dirty == is_dirty:
		return
	_dirty = is_dirty
	_refresh_status()

func has_unsaved_changes() -> bool:
	return _dirty

func request_window_close(on_close: Callable) -> void:
	if not has_unsaved_changes():
		if on_close.is_valid():
			on_close.call()
		return

	_pending_close_callback = on_close
	_close_confirmation_dialog.dialog_text = "There are unsaved Gameplay Tags changes. Save them before closing?"
	_close_confirmation_dialog.popup_centered(Vector2i(420, 180))

func _refresh_path_hint() -> void:
	if _path_hint_label == null:
		return

	var target_path: String = _path_edit.text.strip_edges()
	if target_path.is_empty():
		target_path = DEFAULT_CONFIG_PATH

	_path_hint_label.text = "Default source: %s. Save will create the file if it does not exist." % DEFAULT_CONFIG_PATH
	if target_path != DEFAULT_CONFIG_PATH:
		_path_hint_label.text += " Current target: %s" % target_path

func _update_tag_summary(visible_count: int, explicit_count: int, filter_text: String) -> void:
	if _tag_summary_label == null:
		return

	var summary: String = "Visible tags: %d | Explicit tags: %d" % [visible_count, explicit_count]
	if not filter_text.is_empty():
		summary += " | Filter: %s" % filter_text
	_tag_summary_label.text = summary

func _add_placeholder_item(root: TreeItem, message: String) -> void:
	var placeholder: TreeItem = _tag_tree.create_item(root)
	placeholder.set_text(0, message)
	placeholder.set_selectable(0, false)
	_update_tag_summary(0, 0, _search_edit.text.strip_edges().to_lower() if _search_edit else "")

func _on_reset_path_pressed() -> void:
	_path_edit.text = DEFAULT_CONFIG_PATH
	_refresh_path_hint()
	_set_result_message("Result: Config path reset to the project default.")

func _on_reload_pressed() -> void:
	if _manager == null or not _manager.has_method("reload_tags"):
		_set_result_message("Result: GameplayTags manager is unavailable.")
		return

	var success: bool = bool(_manager.call("reload_tags", _path_edit.text))
	if success:
		_set_dirty_state(false)
	_refresh_all()
	_set_result_message("Result: Reload %s." % ("succeeded" if success else "failed"))

func _on_save_pressed() -> void:
	_perform_save(true)

func _on_search_changed(_new_text: String) -> void:
	_refresh_tree()
	_refresh_selection_details()

func _on_tree_item_selected() -> void:
	var selected_item: TreeItem = _tag_tree.get_selected()
	if selected_item == null:
		_selected_tag = StringName()
		_refresh_selection_details()
		return

	var metadata: Variant = selected_item.get_metadata(0)
	if metadata == null:
		_selected_tag = StringName()
	else:
		_selected_tag = StringName(str(metadata))
	_refresh_selection_details()

func _on_tag_tree_gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return

	var mouse_event: InputEventMouseButton = event
	if not mouse_event.pressed or mouse_event.button_index != MOUSE_BUTTON_RIGHT:
		return

	var clicked_item: TreeItem = _tag_tree.get_item_at_position(mouse_event.position)
	if clicked_item != null:
		clicked_item.select(0)
		var metadata: Variant = clicked_item.get_metadata(0)
		_selected_tag = StringName("" if metadata == null else str(metadata))
		_refresh_selection_details()

	if String(_selected_tag).is_empty():
		return

	_tree_context_menu.position = DisplayServer.mouse_get_position()
	_tree_context_menu.popup()

func _on_add_pressed() -> void:
	if _add_dialog == null:
		return
	_add_dialog_input.text = ""
	_add_dialog.popup_centered_ratio(0.3)

func _on_add_child_pressed() -> void:
	if _add_dialog == null:
		return

	var selected_tag_text: String = String(_selected_tag)
	if selected_tag_text.is_empty():
		_set_result_message("Result: Select a parent tag first.")
		return

	_add_dialog_input.text = "%s." % selected_tag_text
	_add_dialog.popup_centered_ratio(0.3)
	_add_dialog_input.grab_focus()
	_add_dialog_input.caret_column = _add_dialog_input.text.length()

func _on_expand_all_pressed() -> void:
	_set_tree_collapsed_state(false)

func _on_collapse_all_pressed() -> void:
	_set_tree_collapsed_state(true)

func _on_rename_pressed() -> void:
	if String(_selected_tag).is_empty():
		_set_result_message("Result: Select a tag to rename.")
		return
	if _rename_dialog == null:
		return
	_rename_dialog_input.text = String(_selected_tag)
	_update_rename_preview(_rename_dialog_input.text)
	_rename_dialog.popup_centered_ratio(0.3)

func _on_remove_pressed() -> void:
	if String(_selected_tag).is_empty():
		_set_result_message("Result: Select a tag to remove.")
		return
	if _remove_dialog == null:
		return
	_remove_dialog.dialog_text = _build_remove_preview_text(String(_selected_tag))
	_remove_dialog.popup_centered_ratio(0.3)

func _on_add_dialog_confirmed() -> void:
	if _manager == null or not _manager.has_method("add_explicit_tag"):
		_set_result_message("Result: GameplayTags manager is unavailable.")
		return

	var success: bool = bool(_manager.call("add_explicit_tag", _add_dialog_input.text))
	if success:
		_set_dirty_state(true)
		_set_result_message("Result: Added tag '%s'." % _add_dialog_input.text.strip_edges())
		_refresh_all()
		return

	_refresh_status()
	_set_result_message("Result: Failed to add tag.")

func _on_rename_dialog_confirmed() -> void:
	if _manager == null or not _manager.has_method("rename_tag"):
		_set_result_message("Result: GameplayTags manager is unavailable.")
		return

	var success: bool = bool(_manager.call("rename_tag", _selected_tag, _rename_dialog_input.text, true))
	if success:
		_set_dirty_state(true)
		_set_result_message("Result: Renamed '%s' -> '%s'." % [String(_selected_tag), _rename_dialog_input.text])
		_selected_tag = StringName(_rename_dialog_input.text.strip_edges())
		_refresh_all()
		return

	_refresh_status()
	_set_result_message("Result: Rename failed.")

func _on_remove_dialog_confirmed() -> void:
	if _manager == null or not _manager.has_method("remove_explicit_tag"):
		_set_result_message("Result: GameplayTags manager is unavailable.")
		return

	var success: bool = bool(_manager.call("remove_explicit_tag", _selected_tag, true))
	if success:
		_set_dirty_state(true)
		_set_result_message("Result: Removed '%s' and descendants." % String(_selected_tag))
		_selected_tag = StringName()
		_refresh_all()
		return

	_refresh_status()
	_set_result_message("Result: Remove failed.")

func _on_evaluate_query_pressed() -> void:
	if _manager == null:
		_set_result_message("Result: GameplayTags manager is unavailable.")
		return

	var container_tags: Array[StringName] = _parse_csv_tags(_container_input.text)
	var container: GameplayTagContainer = GameplayTagContainer.new()
	for tag_name in container_tags:
		container.add_tag(tag_name)

	var parsed_json: Variant = JSON.parse_string(_query_input.text)
	if not (parsed_json is Dictionary):
		_set_result_message("Result: Query JSON must parse to a Dictionary.")
		return

	var query: GameplayTagQuery = GameplayTagQuery.from_dict(parsed_json)
	var result: bool = false
	if _manager.has_method("evaluate_query"):
		result = bool(_manager.call("evaluate_query", container, query))
	else:
		result = query.evaluate(container)

	_set_result_message("Result: %s" % ("MATCH" if result else "NO MATCH"))

func _on_use_selected_as_container_pressed() -> void:
	var selected_tag_text: String = String(_selected_tag)
	if selected_tag_text.is_empty():
		_set_result_message("Result: Select a tag first.")
		return

	_container_input.text = selected_tag_text
	_set_result_message("Result: Selected tag copied into the container field.")

func _on_use_selected_in_query_pressed() -> void:
	var selected_tag_text: String = String(_selected_tag)
	if selected_tag_text.is_empty():
		_set_result_message("Result: Select a tag first.")
		return

	_query_input.text = JSON.stringify(
		{
			"type": "all_tags",
			"tags": [selected_tag_text],
			"expressions": []
		},
		"  "
	)
	_set_result_message("Result: Query template updated from the selected tag.")

func _on_find_references_pressed() -> void:
	var selected_tag_text: String = String(_selected_tag)
	if selected_tag_text.is_empty():
		_set_result_message("Result: Select a tag first.")
		return

	var references: Array[String] = _find_tag_references(selected_tag_text)
	_refresh_reference_results(selected_tag_text, references)
	_set_result_message("Result: Reference scan completed for '%s'." % selected_tag_text)

func _on_rename_input_changed(new_text: String) -> void:
	_update_rename_preview(new_text)

func _on_tree_context_menu_id_pressed(menu_id: int) -> void:
	match menu_id:
		TREE_MENU_COPY_TAG:
			DisplayServer.clipboard_set(String(_selected_tag))
			_set_result_message("Result: Tag name copied to clipboard.")
		TREE_MENU_ADD_CHILD:
			_on_add_child_pressed()
		TREE_MENU_USE_AS_CONTAINER:
			_on_use_selected_as_container_pressed()
		TREE_MENU_USE_IN_QUERY:
			_on_use_selected_in_query_pressed()

func _set_tree_collapsed_state(collapsed: bool) -> void:
	if _tag_tree == null:
		return

	var root: TreeItem = _tag_tree.get_root()
	if root == null:
		return

	var child: TreeItem = root.get_first_child()
	while child != null:
		_set_tree_item_collapsed_recursive(child, collapsed)
		child = child.get_next()

func _set_tree_item_collapsed_recursive(item: TreeItem, collapsed: bool) -> void:
	item.set_collapsed(collapsed)
	var child: TreeItem = item.get_first_child()
	while child != null:
		_set_tree_item_collapsed_recursive(child, collapsed)
		child = child.get_next()

func _update_rename_preview(candidate_name: String) -> void:
	if _rename_preview_label == null:
		return

	var old_tag_text: String = String(_selected_tag)
	var normalized_new_name: String = candidate_name.strip_edges()
	if old_tag_text.is_empty():
		_rename_preview_label.text = "Preview: select a tag to rename."
		return
	if normalized_new_name.is_empty():
		_rename_preview_label.text = "Preview: enter the new tag name to see affected descendants."
		return

	var affected_tags: Array[String] = _get_affected_explicit_tags(old_tag_text)
	var references: Array[String] = _find_tag_references(old_tag_text)
	var preview_lines: Array[String] = []
	for affected_tag in affected_tags.slice(0, 3):
		var suffix: String = affected_tag.substr(old_tag_text.length())
		preview_lines.append("%s -> %s%s" % [affected_tag, normalized_new_name, suffix])
	var preview_text: String = "Preview: %d explicit tag(s) will be renamed." % affected_tags.size()
	preview_text += " Project references to update manually: %d." % references.size()
	if not preview_lines.is_empty():
		preview_text += " " + " | ".join(preview_lines)
	if affected_tags.size() > 3:
		preview_text += " | ..."
	if not references.is_empty():
		preview_text += " Referenced by: %s" % ", ".join(references.slice(0, 3))
		if references.size() > 3:
			preview_text += ", ..."
	_rename_preview_label.text = preview_text

func _build_remove_preview_text(tag_text: String) -> String:
	var affected_tags: Array[String] = _get_affected_explicit_tags(tag_text)
	var references: Array[String] = _find_tag_references(tag_text)
	if affected_tags.is_empty():
		if references.is_empty():
			return "Remove '%s' and all descendants?" % tag_text
		return "Remove '%s'? Project references found in %d file(s).\n%s" % [
			tag_text,
			references.size(),
			"\n".join(references.slice(0, 5))
		]

	var preview_text: String = "Remove '%s'? This will delete %d explicit tag(s)." % [tag_text, affected_tags.size()]
	var preview_lines: Array[String] = affected_tags.slice(0, 5)
	if not preview_lines.is_empty():
		preview_text += "\n" + "\n".join(preview_lines)
	if affected_tags.size() > 5:
		preview_text += "\n..."
	if not references.is_empty():
		preview_text += "\nProject references found in %d file(s):" % references.size()
		preview_text += "\n" + "\n".join(references.slice(0, 5))
		if references.size() > 5:
			preview_text += "\n..."
	return preview_text

func _get_affected_explicit_tags(root_tag: String) -> Array[String]:
	var affected_tags: Array[String] = []
	if _manager == null or not _manager.has_method("get_explicit_tags"):
		return affected_tags

	for explicit_tag in _manager.call("get_explicit_tags"):
		var explicit_text: String = String(explicit_tag)
		if explicit_text == root_tag or explicit_text.begins_with("%s." % root_tag):
			affected_tags.append(explicit_text)
	affected_tags.sort()
	return affected_tags

func _find_tag_references(tag_text: String) -> Array[String]:
	var references: Array[String] = []
	_scan_reference_directory("res://", tag_text, references)
	references.sort()
	return references

func _scan_reference_directory(directory_path: String, tag_text: String, references: Array[String]) -> void:
	var dir: DirAccess = DirAccess.open(directory_path)
	if dir == null:
		return

	dir.list_dir_begin()
	while true:
		var entry_name: String = dir.get_next()
		if entry_name.is_empty():
			break
		if entry_name == "." or entry_name == "..":
			continue

		var entry_path: String = "%s/%s" % [directory_path.trim_suffix("/"), entry_name]
		if dir.current_is_dir():
			if _should_skip_reference_path(entry_path):
				continue
			_scan_reference_directory(entry_path, tag_text, references)
			continue

		if _should_skip_reference_path(entry_path):
			continue
		if not _is_reference_searchable_file(entry_path):
			continue
		if _file_contains_tag_reference(entry_path, tag_text):
			references.append(entry_path)
	dir.list_dir_end()

func _should_skip_reference_path(path: String) -> bool:
	for excluded_prefix in REFERENCE_SCAN_EXCLUDED_PREFIXES:
		if path.begins_with(excluded_prefix):
			return true
	for excluded_file in REFERENCE_SCAN_EXCLUDED_FILES:
		if path == excluded_file:
			return true
	return false

func _is_reference_searchable_file(path: String) -> bool:
	var extension: String = path.get_extension().to_lower()
	return SEARCHABLE_REFERENCE_EXTENSIONS.has(extension)

func _file_contains_tag_reference(path: String, tag_text: String) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false

	var contents: String = file.get_as_text()
	return contents.contains(tag_text)

func _parse_csv_tags(csv_text: String) -> Array[StringName]:
	var result: Array[StringName] = []
	for raw_segment in csv_text.split(",", false):
		var normalized: String = str(raw_segment).strip_edges()
		if normalized.is_empty():
			continue
		result.append(StringName(normalized))
	return result

func _set_result_message(message: String) -> void:
	if _query_result_label:
		_query_result_label.text = message

func _get_validation_issues() -> Array[String]:
	if _manager == null or not _manager.has_method("validate_registry"):
		return []
	return _manager.call("validate_registry")

func _perform_save(show_feedback: bool = true) -> bool:
	if _manager == null or not _manager.has_method("save_registry"):
		if show_feedback:
			_set_result_message("Result: GameplayTags manager is unavailable.")
		return false

	var validation_issues: Array[String] = _get_validation_issues()
	if not validation_issues.is_empty():
		_refresh_warnings_panel()
		if show_feedback:
			_set_result_message("Result: Fix validation issues before saving.")
		return false

	var success: bool = bool(_manager.call("save_registry", _path_edit.text))
	if success:
		_set_dirty_state(false)
	_refresh_all()
	if show_feedback:
		_set_result_message("Result: Save %s." % ("succeeded" if success else "failed"))
	return success

func _on_close_dialog_confirmed() -> void:
	if not _perform_save(true):
		return
	_finish_pending_close()

func _on_close_dialog_custom_action(action: StringName) -> void:
	if String(action) != "discard":
		return
	_finish_pending_close()

func _on_close_dialog_canceled() -> void:
	_pending_close_callback = Callable()

func _finish_pending_close() -> void:
	var callback: Callable = _pending_close_callback
	_pending_close_callback = Callable()
	if callback.is_valid():
		callback.call()

func _on_registry_changed() -> void:
	_refresh_all()

func _on_registry_reloaded(_tag_count: int, _warning_count: int) -> void:
	_refresh_all()

func _resolve_manager() -> Node:
	var autoload_manager: Node = _resolve_autoload_manager()
	if autoload_manager:
		return autoload_manager

	if _local_manager == null:
		var manager_script: Script = load(MANAGER_SCRIPT_PATH)
		if manager_script == null:
			return null
		var manager_instance: Variant = manager_script.new()
		if not (manager_instance is Node):
			return null
		_local_manager = manager_instance
		if _local_manager.has_method("reload_tags"):
			_local_manager.call("reload_tags", DEFAULT_CONFIG_PATH)

	return _local_manager

func _resolve_autoload_manager() -> Node:
	if get_tree() == null or get_tree().root == null:
		return null
	return get_tree().root.get_node_or_null("GameplayTags")
