@tool
extends VBoxContainer

const ContentBrowserPresenter = preload("res://addons/cdc_game_editor/content_browser_presenter.gd")
const ContentEditService = preload("res://scripts/data/content_edit_service.gd")
const ContentRegistry = preload("res://scripts/data/content_registry.gd")

var repo_root: String = ""
var registry: ContentRegistry
var presenter: ContentBrowserPresenter
var edit_service: ContentEditService
var selected_kind := "item"
var selected_id := ""
var rows: Array[Dictionary] = []
var edit_inputs: Dictionary = {}

var status_label: Label
var kind_option: OptionButton
var filter_edit: LineEdit
var list: ItemList
var form_container: VBoxContainer
var detail: RichTextLabel


func _ready() -> void:
	repo_root = ProjectSettings.globalize_path("res://..").simplify_path()
	registry = ContentRegistry.new()
	presenter = ContentBrowserPresenter.new()
	edit_service = ContentEditService.new()
	_build_ui()
	_refresh_registry()


func _build_ui() -> void:
	name = "CDC Content Browser"
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	var title := Label.new()
	title.text = "CDC Content Browser"
	title.add_theme_font_size_override("font_size", 16)
	add_child(title)

	status_label = Label.new()
	status_label.text = "Status: loading content"
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(status_label)

	kind_option = OptionButton.new()
	for kind in presenter.supported_kinds():
		kind_option.add_item(kind)
	kind_option.item_selected.connect(_on_kind_selected)
	add_child(kind_option)

	filter_edit = LineEdit.new()
	filter_edit.placeholder_text = "Filter id or name"
	filter_edit.text_changed.connect(_on_filter_changed)
	add_child(filter_edit)

	var refresh_button := Button.new()
	refresh_button.text = "Refresh"
	refresh_button.pressed.connect(_on_refresh_pressed)
	add_child(refresh_button)

	list = ItemList.new()
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.item_selected.connect(_on_item_selected)
	add_child(list)

	form_container = VBoxContainer.new()
	add_child(form_container)

	detail = RichTextLabel.new()
	detail.fit_content = true
	detail.scroll_active = true
	detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail.text = "Select a content record."
	add_child(detail)


func _refresh_registry() -> void:
	var result := registry.load_all()
	if result.has_errors():
		status_label.text = "Status: content load failed"
		detail.text = "\n".join(result.errors)
		return
	var overview := presenter.build_overview(registry)
	status_label.text = "Status: %d records | %d invalid" % [
		int(overview.get("total_records", 0)),
		int(overview.get("invalid_records", 0)),
	]
	_refresh_rows()


func _refresh_rows() -> void:
	rows = presenter.rows_for_kind(selected_kind, registry, filter_edit.text)
	list.clear()
	for row in rows:
		var row_data: Dictionary = row
		var label := "%s  %s  [%s]" % [
			row_data.get("id", ""),
			row_data.get("label", ""),
			row_data.get("status", ""),
		]
		list.add_item(label)
	if rows.is_empty():
		detail.text = "No %s records match the current filter." % selected_kind
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
	var detail_data := presenter.build_detail(selected_kind, selected_id, registry, repo_root)
	detail.text = str(detail_data.get("text", "Failed to build content detail."))


func _refresh_form() -> void:
	for child in form_container.get_children():
		child.queue_free()
	edit_inputs.clear()
	var domain: String = presenter.domain_for_kind(selected_kind)
	if domain.is_empty():
		return
	var record: Dictionary = registry.get_library(domain).get(selected_id, {})
	var data: Dictionary = _dictionary_or_empty(record.get("data", {}))
	for field in edit_service.editable_fields(domain):
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = "%s (%s)" % [field, edit_service.field_type(domain, field)]
		label.custom_minimum_size = Vector2(160, 0)
		row.add_child(label)
		var input := LineEdit.new()
		input.text = str(_get_field(data, field))
		input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(input)
		form_container.add_child(row)
		edit_inputs[field] = input
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


func _on_kind_selected(index: int) -> void:
	selected_kind = kind_option.get_item_text(index)
	selected_id = ""
	_refresh_rows()


func _on_filter_changed(_new_text: String) -> void:
	selected_id = ""
	_refresh_rows()


func _on_refresh_pressed() -> void:
	_refresh_registry()


func _on_item_selected(index: int) -> void:
	_select_row(index)


func apply_patch_for_current_selection(patch: Dictionary, dry_run: bool = false, options: Dictionary = {}) -> Dictionary:
	var domain: String = presenter.domain_for_kind(selected_kind)
	var save_options := options.duplicate()
	save_options["dry_run"] = dry_run
	var report := edit_service.save_patch(domain, selected_id, patch, registry, save_options)
	if bool(report.get("ok", false)) and not dry_run:
		if status_label != null:
			_refresh_registry()
	return report


func _on_dry_run_pressed() -> void:
	_save_current_patch(true)


func _on_save_pressed() -> void:
	_save_current_patch(false)


func _save_current_patch(dry_run: bool) -> void:
	var patch: Dictionary = {}
	for field in edit_inputs.keys():
		var input: LineEdit = edit_inputs[field]
		patch[field] = input.text
	var report := apply_patch_for_current_selection(patch, dry_run)
	if not bool(report.get("ok", false)):
		status_label.text = "Status: save failed"
		detail.text = "save_failed:\n%s" % JSON.stringify(report, "\t")
		return
	status_label.text = "Status: dry run ok" if dry_run else "Status: saved %s" % report.get("relative_path", "")
	if dry_run:
		detail.text = "dry_run:\n%s" % JSON.stringify(report, "\t")


func _get_field(data: Dictionary, field_path: String) -> Variant:
	var current: Variant = data
	for part in field_path.split(".", false):
		if typeof(current) != TYPE_DICTIONARY:
			return ""
		var dict: Dictionary = current
		current = dict.get(part, "")
	return current


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}
