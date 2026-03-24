extends InteractionOption
class_name ExitToOutdoorInteractionOption
## LEGACY AUTHORITY BOUNDARY:
## Exit travel wiring is kept as a Godot compatibility shell. Do not add new
## authoritative travel/context rules here; long-term ownership belongs to
## Rust runtime/protocol with Godot handling presentation and command dispatch.

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
