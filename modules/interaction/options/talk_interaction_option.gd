extends InteractionOption
class_name TalkInteractionOption

@export var speaker_name: String = "NPC"
@export_multiline var dialogue_text: String = "你好。"
@export var portrait_path: String = ""

func _init() -> void:
	option_id = "talk"
	display_name = "交谈"
	priority = 800

func execute(interactable: Node) -> void:
	var final_text := dialogue_text
	if final_text.is_empty():
		final_text = "你和 %s 交谈。" % interactable.name
	
	if DialogModule:
		DialogModule.show_dialog(final_text, speaker_name, portrait_path)
	
	if EventBus:
		EventBus.emit(EventBus.EventType.SCENE_INTERACTION, {
			"type": "talk",
			"target": interactable.name,
			"speaker": speaker_name
		})
