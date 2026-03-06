extends "res://core/base_module.gd"
# 注意: 作为 Autoload 单例，不使用 class_name

signal dialog_started(text: String, speaker: String)
signal choice_selected(index: int, choice_text: String)
signal dialog_finished()
signal dialog_hidden()

var _dialog_ui: DialogUI

func _ready():
	# 延迟加载UI，避免 _ready 时场景树不完整
	call_deferred("_setup_ui")

func _setup_ui():
	# Load dialog UI
	if not FileAccess.file_exists("res://modules/dialog/dialog_ui.tscn"):
		push_error("[DialogModule] dialog_ui.tscn not found!")
		return
	
	var dialog_scene = load("res://modules/dialog/dialog_ui.tscn")
	if not dialog_scene:
		push_error("[DialogModule] Failed to load dialog_ui.tscn")
		return
	
	_dialog_ui = dialog_scene.instantiate()
	if not _dialog_ui:
		push_error("[DialogModule] Failed to instantiate dialog UI")
		return
	
	get_tree().root.add_child(_dialog_ui)
	if _dialog_ui.has_method("hide_dialog"):
		_dialog_ui.hide_dialog()
	
	# Connect UI signals
	if _dialog_ui.has_signal("text_finished"):
		_dialog_ui.text_finished.connect(_on_text_finished)
	if _dialog_ui.has_signal("choice_made"):
		_dialog_ui.choice_made.connect(_on_choice_made)

func show_dialog(text: String, speaker: String = "", portrait: String = ""):
	if not _validate_input({
		"text": text
	}, ["text"]):
		return
	
	dialog_started.emit(text, speaker)
	_dialog_ui.show_text(text, speaker, portrait)

func show_choices(choices: Array[String]):
	if not _validate_input({
		"choices": choices
	}, ["choices"]):
		return -1
	
	# 注意: 这是一个协程，调用处需要使用 await
	return await _dialog_ui.show_choices(choices)

func hide_dialog():
	_dialog_ui.hide_dialog()
	dialog_hidden.emit()

func _on_text_finished():
	dialog_finished.emit()

func _on_choice_made(index: int, choice_text: String):
	choice_selected.emit(index, choice_text)
