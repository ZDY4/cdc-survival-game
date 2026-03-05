extends Resource
class_name InteractionOption

@export var option_id: String = "interact"
@export var display_name: String = "Interact"
@export_multiline var description: String = ""
@export var priority: int = 100
@export var enabled: bool = true

func get_option_name(_interactable: Node) -> String:
	if not display_name.is_empty():
		return display_name
	return option_id.capitalize()

func is_available(_interactable: Node) -> bool:
	return enabled

func execute(_interactable: Node) -> void:
	push_warning("InteractionOption.execute() should be overridden by subclasses.")
