@tool
extends StaticBody3D
class_name SubsceneEntry

const EnterSubsceneInteractionOption = preload("res://modules/interaction/options/enter_subscene_interaction_option.gd")

@export var prompt_text: String = "进入室内":
	set(value):
		prompt_text = value
		_refresh_visuals()

@export var target_location_id: String = ""
@export var return_spawn_id: String = "default_spawn"

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
	var option := EnterSubsceneInteractionOption.new()
	option.display_name = prompt_text
	option.target_location_id = target_location_id
	option.return_spawn_id = return_spawn_id
	_interactable.set_options([option])
	_interactable.interaction_name = prompt_text
