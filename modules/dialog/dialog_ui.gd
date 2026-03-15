extends Control

class_name DialogUI

signal text_finished()
signal choice_made(index: int, choice_text: String)

@export var text_speed: float = 0.05

# Node references
var _dialog_label: RichTextLabel
var _speaker_label: Label
var _portrait_container: TextureRect
var _choices_scroll: ScrollContainer
var _choices_container: VBoxContainer
var _next_indicator: Label

# State
var _is_typing: bool = false
var _is_waiting_for_continue: bool = false
var _current_text: String = ""
var _current_speaker: String = ""
var _choice_result: int = -1
var _is_mobile: bool = false

func _ready():
	_is_mobile = OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")
	call_deferred("_setup_nodes")

func _setup_nodes():
	_dialog_label = get_node_or_null("Panel/MarginContainer/MainRow/ContentColumn/TextLabel")
	_speaker_label = get_node_or_null("Panel/MarginContainer/MainRow/ContentColumn/NameLabel")
	_portrait_container = get_node_or_null("Panel/MarginContainer/MainRow/Portrait")
	_choices_scroll = get_node_or_null("Panel/MarginContainer/MainRow/ContentColumn/ChoicesScroll")
	_choices_container = get_node_or_null("Panel/MarginContainer/MainRow/ContentColumn/ChoicesScroll/ChoicesContainer")
	_next_indicator = get_node_or_null("Panel/MarginContainer/MainRow/ContentColumn/FooterRow/NextIndicator")

func show_text(text: String, speaker: String = "", portrait: String = ""):
	_is_typing = true
	_is_waiting_for_continue = false
	_current_text = text
	_current_speaker = speaker
	
	if _speaker_label:
		_speaker_label.text = speaker
	
	_set_portrait(portrait)
	
	if _dialog_label:
		_dialog_label.text = ""
		_dialog_label.scroll_to_line(0)
	if _next_indicator:
		_next_indicator.visible = false
	if _choices_scroll:
		_choices_scroll.visible = false
	if _choices_container:
		_choices_container.visible = false
	
	visible = true
	_start_typing(text)

func _start_typing(text: String):
	for i in range(text.length()):
		if not _is_typing:
			break
		if _dialog_label:
			_dialog_label.text = text.substr(0, i + 1)
		await get_tree().create_timer(text_speed).timeout
	
	_is_typing = false
	_is_waiting_for_continue = true
	if _next_indicator:
		_next_indicator.visible = true

func show_choices(choices: Array[String]):
	_is_typing = false
	_is_waiting_for_continue = false
	if _choices_scroll:
		_choices_scroll.visible = true
		_choices_scroll.scroll_vertical = 0
	if _choices_container:
		_choices_container.visible = true
	if _next_indicator:
		_next_indicator.visible = false
	if _dialog_label:
		_dialog_label.text = ""
	_choice_result = -1
	
	# Clear existing buttons
	if _choices_container:
		for child in _choices_container.get_children():
			child.queue_free()
	
		# Create new buttons with mobile-friendly sizes
		for i in range(choices.size()):
			var button = Button.new()
			button.text = choices[i]
			button.pressed.connect(_on_choice_button_pressed.bind(i, choices[i]))
			
			# Mobile: larger buttons for touch
			if _is_mobile:
				button.custom_minimum_size = Vector2(0, 72)
				button.add_theme_font_size_override("font_size", 24)
			
			_choices_container.add_child(button)
	
	# Wait for choice
	await choice_made
	return _choice_result

func _on_choice_button_pressed(index: int, choice_text: String):
	_choice_result = index
	choice_made.emit(index, choice_text)
	hide_dialog()

func hide_dialog():
	_is_typing = false
	_is_waiting_for_continue = false
	visible = false
	if _dialog_label:
		_dialog_label.text = ""
		_dialog_label.scroll_to_line(0)
	if _speaker_label:
		_speaker_label.text = ""
	_clear_portrait()
	if _choices_scroll:
		_choices_scroll.visible = false
	if _choices_container:
		_choices_container.visible = false
	if _next_indicator:
		_next_indicator.visible = false

func _input(event):
	if not visible or _is_choices_visible():
		return
	
	if event is InputEventScreenTouch:
		if event.pressed and _is_mouse_inside_dialog(event.position):
			advance_dialog()
	elif event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT and _is_mouse_inside_dialog(event.position):
			advance_dialog()
	elif event is InputEventKey:
		if event.pressed and not event.echo and _is_advance_key(event.keycode):
			advance_dialog()

func advance_dialog() -> void:
	if _is_choices_visible():
		return
	
	if _is_typing:
		_finish_typing()
		return
	
	if not _is_waiting_for_continue:
		return
	
	_is_waiting_for_continue = false
	if _next_indicator:
		_next_indicator.visible = false
	hide_dialog()
	text_finished.emit()

func _finish_typing() -> void:
	_is_typing = false
	_is_waiting_for_continue = true
	if _dialog_label:
		_dialog_label.text = _current_text
	if _next_indicator:
		_next_indicator.visible = true

func _set_portrait(portrait_path: String) -> void:
	if not _portrait_container:
		return
	
	if portrait_path.is_empty():
		_clear_portrait()
		return
	
	var portrait_texture := load(portrait_path) as Texture2D
	if portrait_texture:
		_portrait_container.texture = portrait_texture
		_portrait_container.visible = true
		return
	
	_clear_portrait()

func _clear_portrait() -> void:
	if not _portrait_container:
		return
	
	_portrait_container.texture = null
	_portrait_container.visible = false

func _is_choices_visible() -> bool:
	return _choices_scroll != null and _choices_scroll.visible

func _is_mouse_inside_dialog(pointer_position: Vector2) -> bool:
	return get_global_rect().has_point(pointer_position)

func _is_advance_key(keycode: Key) -> bool:
	return keycode == KEY_SPACE or keycode == KEY_ENTER or keycode == KEY_KP_ENTER
