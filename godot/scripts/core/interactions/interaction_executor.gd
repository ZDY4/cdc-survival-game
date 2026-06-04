extends RefCounted

const InteractionActionRunner = preload("res://scripts/core/interactions/interaction_action_runner.gd")
const InteractionTargetResolver = preload("res://scripts/core/interactions/interaction_target_resolver.gd")

var _action_runner := InteractionActionRunner.new()
var _target_resolver := InteractionTargetResolver.new()


func query(simulation: RefCounted, actor_id: int, target: Dictionary) -> Dictionary:
	return _target_resolver.query(simulation, actor_id, target)


func execute(simulation: RefCounted, actor_id: int, target: Dictionary, option_id: String = "") -> Dictionary:
	var prompt: Dictionary = query(simulation, actor_id, target)
	if not bool(prompt.get("ok", false)):
		return {
			"success": false,
			"reason": prompt.get("reason", "interaction_unavailable"),
			"prompt": prompt,
		}

	var option: Dictionary = _find_enabled_option(prompt, option_id)
	if option.is_empty():
		var disabled_option: Dictionary = _find_disabled_option(prompt, option_id)
		var reason: String = str(disabled_option.get("disabled_reason", "interaction_option_unavailable"))
		return {
			"success": false,
			"reason": reason,
			"prompt": prompt,
		}
	return _action_runner.execute(simulation, actor_id, prompt, option)


func _find_enabled_option(prompt: Dictionary, option_id: String) -> Dictionary:
	var options: Array = prompt.get("options", [])
	if option_id.is_empty() and not options.is_empty():
		return _dictionary_or_empty(options[0])
	for candidate in options:
		var option: Dictionary = _dictionary_or_empty(candidate)
		if str(option.get("id", "")) == option_id:
			return option
	return {}


func _find_disabled_option(prompt: Dictionary, option_id: String) -> Dictionary:
	if option_id.is_empty():
		return {}
	for candidate in prompt.get("disabled_options", []):
		var option: Dictionary = _dictionary_or_empty(candidate)
		if str(option.get("id", "")) == option_id:
			return option
	return {}


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}
