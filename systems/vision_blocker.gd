class_name VisionBlocker
extends Node3D
## Marks a node as blocking vision for grid-based vision.

@export var blocks_vision: bool = true

func _ready() -> void:
	if blocks_vision:
		add_to_group("vision_blocker")

func _exit_tree() -> void:
	if blocks_vision:
		remove_from_group("vision_blocker")
