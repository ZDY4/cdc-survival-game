@tool
extends StaticBody3D
class_name OverworldEntry
## LEGACY AUTHORITY BOUNDARY:
## This node is a compatibility front-end entrypoint for overworld transition.
## Keep it limited to option/presentation wiring, and avoid adding new
## authoritative travel/context logic on the Godot side.

const EnterOverworldInteractionOption = preload("res://modules/interaction/options/enter_overworld_interaction_option.gd")
const InteractableScript = preload("res://modules/interaction/interactable.gd")

@export var prompt_text: String = "进入大地图":
	set(value):
		prompt_text = value
		_refresh_visuals()

@onready var _interactable: Node = get_node_or_null("Interactable") as Node
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
	var option: Resource = EnterOverworldInteractionOption.new()
	option.display_name = prompt_text
	_interactable.set_options([option])
	_interactable.interaction_name = prompt_text
