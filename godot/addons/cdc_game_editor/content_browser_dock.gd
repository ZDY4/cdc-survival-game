@tool
extends VBoxContainer

const ContentBrowserPresenter = preload("res://addons/cdc_game_editor/content_browser_presenter.gd")
const ContentRegistry = preload("res://scripts/data/content_registry.gd")

var repo_root: String = ""
var registry: ContentRegistry
var presenter: ContentBrowserPresenter
var selected_kind := "item"
var selected_id := ""
var rows: Array[Dictionary] = []

var status_label: Label
var kind_option: OptionButton
var filter_edit: LineEdit
var list: ItemList
var detail: RichTextLabel


func _ready() -> void:
	repo_root = ProjectSettings.globalize_path("res://..").simplify_path()
	registry = ContentRegistry.new()
	presenter = ContentBrowserPresenter.new()
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
	var detail_data := presenter.build_detail(selected_kind, selected_id, registry, repo_root)
	detail.text = str(detail_data.get("text", "Failed to build content detail."))


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
