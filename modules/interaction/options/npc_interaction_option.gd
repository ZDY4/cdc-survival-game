extends InteractionOption
class_name NPCInteractionOption

@export var npc_id_override: String = ""

func _init() -> void:
	option_id = "npc_interact"
	display_name = "交谈"
	priority = 800

func is_available(interactable: Node) -> bool:
	if not enabled:
		return false
	return not _resolve_npc_id(interactable).is_empty()

func execute(interactable: Node) -> void:
	var npc_id := _resolve_npc_id(interactable)
	if npc_id.is_empty():
		return
	if not AIManager.current:
		push_warning("[NPCInteractionOption] AIManager.current unavailable; cannot interact with NPC: %s" % npc_id)
		return
	if AIManager.current.has_method("start_npc_interaction"):
		AIManager.current.start_npc_interaction(npc_id)
	if EventBus:
		EventBus.emit(EventBus.EventType.SCENE_INTERACTION, {
			"type": "npc_interact",
			"target": npc_id
		})

func _resolve_npc_id(interactable: Node) -> String:
	if not npc_id_override.is_empty():
		return npc_id_override
	if interactable and interactable.has_meta("npc_id"):
		return str(interactable.get_meta("npc_id"))
	var node := interactable.get_parent() if interactable else null
	while node != null:
		if node.has_meta("npc_id"):
			return str(node.get_meta("npc_id"))
		node = node.get_parent()
	return ""
