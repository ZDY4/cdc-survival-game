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

	var options: Array = prompt.get("options", [])
	var option: Dictionary = options[0]
	if not option_id.is_empty() and option.get("id", "") != option_id:
		return {
			"success": false,
			"reason": "interaction_option_unavailable",
			"prompt": prompt,
		}
	return _action_runner.execute(simulation, actor_id, prompt, option)
