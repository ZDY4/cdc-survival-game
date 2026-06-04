@tool
extends Window

const ContentRecordPresenter = preload("res://addons/cdc_game_editor/content_record_presenter.gd")
const ContentEditService = preload("res://scripts/data/content_edit_service.gd")
const ContentRegistry = preload("res://scripts/data/content_registry.gd")
const TypedFieldForm = preload("res://addons/cdc_game_editor/typed_field_form.gd")

const DEFAULT_SIZE := Vector2i(980, 680)
const LIST_MIN_WIDTH := 300.0

var kind := ""
var registry: ContentRegistry
var presenter: ContentRecordPresenter
var edit_service: ContentEditService
var selected_id := ""
var rows: Array[Dictionary] = []
var edit_inputs: Dictionary = {}

var status_label: Label
var filter_edit: LineEdit
var list: ItemList
var form_container: VBoxContainer
var detail: RichTextLabel


func setup(target_kind: String, display_name: String) -> void:
	kind = target_kind
	title = display_name
	name = display_name


func _ready() -> void:
	min_size = Vector2i(720, 480)
	size = DEFAULT_SIZE
	close_requested.connect(hide)
	registry = ContentRegistry.new()
	presenter = ContentRecordPresenter.new()
	edit_service = ContentEditService.new()
	_build_ui()
	_refresh_registry()


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(root)

	var toolbar := HBoxContainer.new()
	root.add_child(toolbar)

	status_label = Label.new()
	status_label.text = "Status: loading %s" % kind
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	toolbar.add_child(status_label)

	var refresh_button := Button.new()
	refresh_button.text = "Refresh"
	refresh_button.pressed.connect(_on_refresh_pressed)
	toolbar.add_child(refresh_button)

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(split)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(LIST_MIN_WIDTH, 0)
	split.add_child(left)

	filter_edit = LineEdit.new()
	filter_edit.placeholder_text = "Filter id or name"
	filter_edit.text_changed.connect(_on_filter_changed)
	left.add_child(filter_edit)

	list = ItemList.new()
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.item_selected.connect(_on_item_selected)
	left.add_child(list)

	var right := VSplitContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(right)

	var edit_scroll := ScrollContainer.new()
	edit_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(edit_scroll)

	form_container = VBoxContainer.new()
	form_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit_scroll.add_child(form_container)

	detail = RichTextLabel.new()
	detail.fit_content = false
	detail.scroll_active = true
	detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail.text = "Select a record."
	right.add_child(detail)


func _refresh_registry() -> void:
	var result := registry.load_all()
	if result.has_errors():
		status_label.text = "Status: content load failed"
		detail.text = "\n".join(result.errors)
		return
	_refresh_rows()


func _refresh_rows() -> void:
	rows = presenter.rows_for_kind(kind, registry, filter_edit.text)
	list.clear()
	for row in rows:
		var row_data: Dictionary = row
		list.add_item("%s  %s  [%s]" % [
			row_data.get("id", ""),
			row_data.get("label", ""),
			row_data.get("status", ""),
		])

	status_label.text = "Status: %d %s records" % [rows.size(), kind]
	if rows.is_empty():
		selected_id = ""
		TypedFieldForm.clear_container(form_container)
		detail.text = "No %s records match the current filter." % kind
		return
	if selected_id.is_empty():
		_select_row(0)


func _select_row(index: int) -> void:
	if index < 0 or index >= rows.size():
		return
	list.select(index)
	var row: Dictionary = rows[index]
	selected_id = str(row.get("id", ""))
	_refresh_form()
	var repo_root := ProjectSettings.globalize_path("res://..").simplify_path()
	var detail_data := presenter.build_detail(kind, selected_id, registry, repo_root)
	detail.text = str(detail_data.get("text", "Failed to build content detail."))


func _refresh_form() -> void:
	TypedFieldForm.clear_container(form_container)
	edit_inputs.clear()
	var domain := presenter.domain_for_kind(kind)
	if domain.is_empty():
		return
	var record: Dictionary = registry.get_library(domain).get(selected_id, {})
	var data: Dictionary = _dictionary_or_empty(record.get("data", {}))
	var editable_fields := edit_service.editable_fields(domain)
	if editable_fields.is_empty():
		var readonly := Label.new()
		readonly.text = "This record type is read-only here."
		form_container.add_child(readonly)
		return

	for field in editable_fields:
		var field_type := edit_service.field_type(domain, field)
		edit_inputs[field] = TypedFieldForm.add_field_row(
			form_container,
			field,
			field_type,
			TypedFieldForm.get_field(data, field)
		)

	var button_row := HBoxContainer.new()
	var dry_run_button := Button.new()
	dry_run_button.text = "Dry Run"
	dry_run_button.pressed.connect(_on_dry_run_pressed)
	button_row.add_child(dry_run_button)
	var save_button := Button.new()
	save_button.text = "Save"
	save_button.pressed.connect(_on_save_pressed)
	button_row.add_child(save_button)
	form_container.add_child(button_row)


func focus_record(id_value: String) -> void:
	selected_id = id_value
	if rows.is_empty():
		return
	for i in range(rows.size()):
		if str(rows[i].get("id", "")) == id_value:
			_select_row(i)
			return


func _on_refresh_pressed() -> void:
	_refresh_registry()


func _on_filter_changed(_new_text: String) -> void:
	selected_id = ""
	_refresh_rows()


func _on_item_selected(index: int) -> void:
	_select_row(index)


func _on_dry_run_pressed() -> void:
	_save_current_patch(true)


func _on_save_pressed() -> void:
	_save_current_patch(false)


func _save_current_patch(dry_run: bool) -> void:
	var report := apply_patch_for_current_selection(TypedFieldForm.build_patch(edit_inputs), dry_run)
	if not bool(report.get("ok", false)):
		status_label.text = "Status: save failed"
		detail.text = "save_failed:\n%s" % JSON.stringify(report, "\t")
		return
	status_label.text = "Status: dry run ok" if dry_run else "Status: saved %s" % report.get("relative_path", "")
	if dry_run:
		detail.text = "dry_run:\n%s" % JSON.stringify(report, "\t")
	else:
		_refresh_registry()


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func apply_patch_for_current_selection(patch: Dictionary, dry_run: bool = true, extra_options: Dictionary = {}) -> Dictionary:
	var domain := presenter.domain_for_kind(kind)
	var save_options := extra_options.duplicate()
	save_options["dry_run"] = dry_run
	return edit_service.save_patch(domain, selected_id, patch, registry, save_options)


func build_patch_from_inputs() -> Dictionary:
	return TypedFieldForm.build_patch(edit_inputs)
