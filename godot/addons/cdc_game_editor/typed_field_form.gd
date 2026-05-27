@tool
extends RefCounted


static func clear_container(container: Node) -> void:
	for child in container.get_children():
		child.queue_free()


static func add_field_row(container: VBoxContainer, field: String, field_type: String, value: Variant, label_width: float = 160.0) -> Control:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = "%s (%s)" % [field, field_type]
	label.custom_minimum_size = Vector2(label_width, 0)
	row.add_child(label)
	var input := create_field_editor(field_type, value)
	row.add_child(input)
	container.add_child(row)
	return input


static func build_patch(inputs: Dictionary) -> Dictionary:
	var patch: Dictionary = {}
	for field in inputs.keys():
		patch[field] = field_editor_value(inputs[field])
	return patch


static func create_field_editor(field_type: String, value: Variant) -> Control:
	match field_type:
		"bool":
			var checkbox := CheckBox.new()
			checkbox.button_pressed = bool(value)
			checkbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			return checkbox
		"int":
			var spinbox := SpinBox.new()
			spinbox.step = 1.0
			spinbox.rounded = true
			spinbox.allow_greater = true
			spinbox.allow_lesser = true
			spinbox.value = float(value)
			spinbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			return spinbox
		"float":
			var spinbox := SpinBox.new()
			spinbox.step = 0.1
			spinbox.allow_greater = true
			spinbox.allow_lesser = true
			spinbox.value = float(value)
			spinbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			return spinbox
		_:
			var input := LineEdit.new()
			input.text = str(value)
			input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			return input


static func field_editor_value(editor: Control) -> Variant:
	if editor is CheckBox:
		return (editor as CheckBox).button_pressed
	if editor is SpinBox:
		var spinbox := editor as SpinBox
		return int(spinbox.value) if spinbox.rounded else spinbox.value
	if editor is LineEdit:
		return (editor as LineEdit).text
	return null


static func get_field(data: Dictionary, field_path: String) -> Variant:
	var current: Variant = data
	for part in field_path.split(".", false):
		if typeof(current) != TYPE_DICTIONARY:
			return ""
		var dict: Dictionary = current
		current = dict.get(part, "")
	return current
