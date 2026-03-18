extends InteractionOption
class_name TalkInteractionOption

@export var speaker_name: String = "NPC"
@export_multiline var dialogue_text: String = "你好。"
@export var portrait_path: String = ""
@export var dialog_id: String = ""

var _relation_resolver: CharacterRelationResolver = CharacterRelationResolver.new()

func _init() -> void:
	option_id = "talk"
	display_name = "交谈"
	priority = 800

func is_available(interactable: Node) -> bool:
	if not enabled:
		return false

	var character_id := _resolve_character_id(interactable)
	if character_id.is_empty():
		return _is_non_ai_interaction_available()

	return _is_ai_interaction_available(interactable, character_id)

func execute(interactable: Node) -> void:
	var character_id := _resolve_character_id(interactable)
	if not character_id.is_empty():
		await _execute_ai_dialog(interactable, character_id)
		return

	if not await _try_execute_dialog_resource(interactable, dialog_id, speaker_name, portrait_path):
		_show_static_dialog(interactable)

	_emit_interaction_event(interactable, speaker_name, dialog_id)

func _is_non_ai_interaction_available() -> bool:
	var resolved_dialog_id := dialog_id.strip_edges()
	if resolved_dialog_id.is_empty():
		return true
	return _dialog_resource_exists(resolved_dialog_id)

func _is_ai_interaction_available(_interactable: Node, character_id: String) -> bool:
	var character_data := _get_character_data(character_id)
	if character_data.is_empty():
		return false

	var relation_result := _relation_resolver.resolve_for_player(character_id, character_data)
	if str(relation_result.get("resolved_attitude", "")) == "hostile":
		return false

	var resolved_dialog_id := _resolve_ai_dialog_id(character_data)
	if resolved_dialog_id.is_empty():
		return false

	return _dialog_resource_exists(resolved_dialog_id)

func _execute_ai_dialog(interactable: Node, character_id: String) -> void:
	if not _is_ai_interaction_available(interactable, character_id):
		return

	var character_data := _get_character_data(character_id)
	var resolved_dialog_id := _resolve_ai_dialog_id(character_data)
	var resolved_speaker := _resolve_ai_speaker_name(character_data, interactable)
	var resolved_portrait := _resolve_ai_portrait_path(character_data)
	if await _try_execute_dialog_resource(
		interactable,
		resolved_dialog_id,
		resolved_speaker,
		resolved_portrait,
		character_id
	):
		_emit_interaction_event(interactable, resolved_speaker, resolved_dialog_id, character_id)

func _try_execute_dialog_resource(
	interactable: Node,
	resolved_dialog_id: String,
	resolved_speaker: String,
	resolved_portrait: String,
	character_id: String = ""
) -> bool:
	var final_dialog_id := resolved_dialog_id.strip_edges()
	if final_dialog_id.is_empty():
		return false
	if not _dialog_resource_exists(final_dialog_id):
		return false
	if not DialogModule or not DialogModule.has_method("play_dialog_resource"):
		return false

	var actor := _resolve_actor_from_interactable(interactable)
	await DialogModule.play_dialog_resource(final_dialog_id, {
		"character_id": character_id,
		"interactable": interactable,
		"actor": actor,
		"speaker_name": resolved_speaker,
		"portrait_path": resolved_portrait
	})
	return true

func _show_static_dialog(interactable: Node) -> void:
	var final_text := dialogue_text
	if final_text.is_empty():
		final_text = "你和 %s 交谈。" % interactable.name

	if DialogModule:
		DialogModule.show_dialog(final_text, speaker_name, portrait_path)

func _emit_interaction_event(
	interactable: Node,
	resolved_speaker: String,
	resolved_dialog_id: String,
	character_id: String = ""
) -> void:
	if EventBus:
		var interaction_target: String = character_id
		if interaction_target.is_empty() and interactable:
			interaction_target = str(interactable.name)
		EventBus.emit(EventBus.EventType.SCENE_INTERACTION, {
			"type": "talk",
			"target": interaction_target,
			"speaker": resolved_speaker,
			"dialog_id": resolved_dialog_id
		})

func _resolve_character_id(interactable: Node) -> String:
	if interactable and interactable.has_meta("npc_id"):
		return str(interactable.get_meta("npc_id"))
	if interactable and interactable.has_meta("character_id"):
		return str(interactable.get_meta("character_id"))

	var node := interactable.get_parent() if interactable else null
	while node != null:
		if node.has_meta("npc_id"):
			return str(node.get_meta("npc_id"))
		if node.has_meta("character_id"):
			return str(node.get_meta("character_id"))
		node = node.get_parent()
	return ""

func _get_character_data(character_id: String) -> Dictionary:
	if character_id.is_empty():
		return {}
	if AIManager.current and AIManager.current.has_method("get_character_data"):
		return AIManager.current.get_character_data(character_id)
	return {}

func _resolve_ai_dialog_id(character_data: Dictionary) -> String:
	if not dialog_id.strip_edges().is_empty():
		return dialog_id.strip_edges()
	var social: Dictionary = character_data.get("social", {})
	return str(social.get("dialog_id", "")).strip_edges()

func _resolve_ai_speaker_name(character_data: Dictionary, interactable: Node) -> String:
	if not speaker_name.strip_edges().is_empty() and speaker_name != "NPC":
		return speaker_name
	var character_name := str(character_data.get("name", "")).strip_edges()
	if not character_name.is_empty():
		return character_name
	if interactable:
		return str(interactable.name)
	return speaker_name

func _resolve_ai_portrait_path(character_data: Dictionary) -> String:
	if not portrait_path.strip_edges().is_empty():
		return portrait_path
	var visual: Dictionary = character_data.get("visual", {})
	return str(visual.get("portrait_path", "")).strip_edges()

func _dialog_resource_exists(resolved_dialog_id: String) -> bool:
	return FileAccess.file_exists("res://data/dialogues/%s.json" % resolved_dialog_id.strip_edges())

func _resolve_actor_from_interactable(interactable: Node) -> Node:
	var node: Node = interactable
	while node != null:
		if node.has_meta("character_id"):
			return node
		node = node.get_parent()
	return null
