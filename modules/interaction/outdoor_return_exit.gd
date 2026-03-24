@tool
extends StaticBody3D
class_name OutdoorReturnExit
## LEGACY AUTHORITY BOUNDARY:
## This exit node is a temporary Godot-side transition shell. Keep it focused
## on local prompt wiring; avoid introducing new travel authority that should
## be centralized in Rust runtime/protocol.

const ExitToOutdoorInteractionOption = preload("res://modules/interaction/options/exit_to_outdoor_interaction_option.gd")

@export var prompt_text: String = "返回露天区域":
	set(value):
		prompt_text = value
		_refresh_visuals()

@onready var _interactable: Interactable = get_node_or_null("Interactable") as Interactable
@onready var _label: Label3D = get_node_or_null("Label3D") as Label3D

func _ready() -> void:
	_refresh_visuals()
	if Engine.is_editor_hint():
		return
	_apply_interaction_option()

func _refresh_visuals() -> void:
	if _label != null:
		_label.text = prompt_text
	if _interactable != null:
		_interactable.interaction_name = prompt_text

func _apply_interaction_option() -> void:
	if _interactable == null:
		return
	var option := ExitToOutdoorInteractionOption.new()
	option.display_name = prompt_text
	_interactable.set_options([option])
	_interactable.interaction_name = prompt_text
