extends InteractionOption
class_name ExitToOutdoorInteractionOption

@export var required_distance: float = 1.4

func _init() -> void:
	option_id = "exit_to_outdoor"
	display_name = "返回露天区域"
	priority = 860

func requires_proximity(_interactable: Node) -> bool:
	return true

func get_required_distance(_interactable: Node) -> float:
	return required_distance

func execute(_interactable: Node) -> void:
	if MapModule != null and MapModule.has_method("exit_current_subscene_to_outdoor"):
		if MapModule.exit_current_subscene_to_outdoor():
			return
	if DialogModule != null:
		DialogModule.show_dialog("当前无法返回露天区域。", "提示", "")
