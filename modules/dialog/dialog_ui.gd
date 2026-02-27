extends Control

class_name DialogUI

signal text_finished()
signal choice_made(index: int, choice_text: String)

@export var text_speed: float = 0.05

# Node references
var _dialog_label: RichTextLabel
var _speaker_label: Label
var _portrait_container: TextureRect
var _choices_container: VBoxContainer
var _continue_button: Button

# State
var _is_typing: bool = false
var _current_text: String = ""
var _current_speaker: String = ""
var _choice_result: int = -1
var _is_mobile: bool = false

func _ready():
	_is_mobile = OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")
	call_deferred("_setup_nodes")

func _setup_nodes():
	_dialog_label = get_node_or_null("Panel/TextLabel")
	_speaker_label = get_node_or_null("Panel/NameLabel")
	_portrait_container = get_node_or_null("Panel/Portrait")
	_choices_container = get_node_or_null("Panel/ChoicesContainer")
	_continue_button = get_node_or_null("Panel/ContinueButton")
	
	if _continue_button:
		_continue_button.pressed.connect(_on_continue_button_pressed)
		# Mobile: larger touch target
		if _is_mobile:
			_continue_button.custom_minimum_size = Vector2(144, 64)
			_continue_button.add_theme_font_size_override("font_size", 24)

func show_text(text: String, speaker: String = "", portrait: String = ""):
	_is_typing = true
	_current_text = text
	_current_speaker = speaker
	
	if _speaker_label:
		_speaker_label.text = speaker
	
	if portrait != "" and _portrait_container:
		var portrait_texture = load(portrait)
		if portrait_texture:
			_portrait_container.texture = portrait_texture
			_portrait_container.visible = true
	elif _portrait_container:
		_portrait_container.visible = false
	
	if _dialog_label:
		_dialog_label.text = ""
	if _continue_button:
		_continue_button.visible = false
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
	if _continue_button:
		_continue_button.visible = true
	text_finished.emit()

func show_choices(choices: Array[String]):
	_is_typing = false
	if _choices_container:
		_choices_container.visible = true
	if _continue_button:
		_continue_button.visible = false
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
	hide()

func hide_dialog():
	_is_typing = false
	visible = false
	if _dialog_label:
		_dialog_label.text = ""
	if _speaker_label:
		_speaker_label.text = ""
	if _portrait_container:
		_portrait_container.visible = false
	if _choices_container:
		_choices_container.visible = false
	if _continue_button:
		_continue_button.visible = false

func _on_continue_button_pressed():
	if _is_typing:
		_is_typing = false
		if _dialog_label:
			_dialog_label.text = _current_text
		if _continue_button:
			_continue_button.visible = true
	else:
		if _continue_button:
			_continue_button.visible = false
		text_finished.emit()

# Touch support: tap anywhere to continue (mobile only)
func _input(event):
	if not _is_mobile or not visible:
		return
	
	if event is InputEventScreenTouch:
		if event.pressed and not _choices_container.visible:
			_on_continue_button_pressed()
