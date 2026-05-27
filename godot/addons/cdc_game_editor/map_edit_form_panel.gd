@tool
extends RefCounted

signal selected(item_id: String)
signal save_requested(dry_run: bool)

const TypedFieldForm = preload("res://addons/cdc_game_editor/typed_field_form.gd")

var option: OptionButton
var form: VBoxContainer
var item_ids: Array[String] = []
var inputs: Dictionary = {}
var selected_id := ""


func attach(parent: VBoxContainer) -> void:
	var toolbar := HBoxContainer.new()
	parent.add_child(toolbar)

	option = OptionButton.new()
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	option.item_selected.connect(_on_item_selected)
	toolbar.add_child(option)

	form = VBoxContainer.new()
	parent.add_child(form)


func refresh_options(items: Array, id_field: String, label_provider: Callable) -> void:
	item_ids = _sorted_item_ids(items, id_field)
	option.clear()
	for item_id in item_ids:
		var item_data := _item_by_id(items, id_field, item_id)
		option.add_item(_item_label(item_data, item_id, label_provider))

	if item_ids.is_empty():
		selected_id = ""
		refresh_form({}, [], Callable())
		return

	var selected_index := max(0, item_ids.find(selected_id))
	option.select(selected_index)
	selected_id = item_ids[selected_index]


func refresh_form(item_data: Dictionary, fields: Array[String], field_type_provider: Callable) -> void:
	TypedFieldForm.clear_container(form)
	inputs.clear()
	if item_data.is_empty():
		return

	for field in fields:
		var field_type := "string"
		if field_type_provider.is_valid():
			field_type = str(field_type_provider.call(field))
		inputs[field] = TypedFieldForm.add_field_row(
			form,
			field,
			field_type,
			TypedFieldForm.get_field(item_data, field),
			150.0
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
	form.add_child(button_row)


func build_patch() -> Dictionary:
	return TypedFieldForm.build_patch(inputs)


func _on_item_selected(index: int) -> void:
	if index < 0 or index >= item_ids.size():
		return
	selected_id = item_ids[index]
	selected.emit(selected_id)


func _on_dry_run_pressed() -> void:
	save_requested.emit(true)


func _on_save_pressed() -> void:
	save_requested.emit(false)


func _sorted_item_ids(items: Array, id_field: String) -> Array[String]:
	var ids: Array[String] = []
	for item in items:
		var item_data := _dictionary_or_empty(item)
		var item_id := str(item_data.get(id_field, ""))
		if not item_id.is_empty():
			ids.append(item_id)
	ids.sort()
	return ids


func _item_by_id(items: Array, id_field: String, item_id: String) -> Dictionary:
	for item in items:
		var item_data := _dictionary_or_empty(item)
		if str(item_data.get(id_field, "")) == item_id:
			return item_data
	return {}


func _item_label(item_data: Dictionary, item_id: String, label_provider: Callable) -> String:
	if label_provider.is_valid():
		return str(label_provider.call(item_data, item_id))
	return item_id


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}
