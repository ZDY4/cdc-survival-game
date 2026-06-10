extends RefCounted

const PresentationTracker = preload("res://scripts/world/presentation/presentation_tracker.gd")
const PresentationMaterials = preload("res://scripts/world/presentation/presentation_materials.gd")
const PresentationNodeFactory = preload("res://scripts/world/presentation/presentation_node_factory.gd")
const MovementActionPresenter = preload("res://scripts/world/presentation/movement_action_presenter.gd")
const AttackActionPresenter = preload("res://scripts/world/presentation/attack_action_presenter.gd")
const ReloadActionPresenter = preload("res://scripts/world/presentation/reload_action_presenter.gd")
const CombatEventPresenter = preload("res://scripts/world/presentation/combat_event_presenter.gd")
const InteractionActionPresenter = preload("res://scripts/world/presentation/interaction_action_presenter.gd")

var _tracker := PresentationTracker.new()
var _materials := PresentationMaterials.new()
var _node_factory := PresentationNodeFactory.new()
var _movement_presenter := MovementActionPresenter.new()
var _attack_presenter := AttackActionPresenter.new()
var _reload_presenter := ReloadActionPresenter.new()
var _combat_event_presenter := CombatEventPresenter.new()
var _interaction_presenter := InteractionActionPresenter.new()


func _init() -> void:
	_movement_presenter.configure(_tracker, _materials, _node_factory)
	_attack_presenter.configure(_tracker, _materials, _node_factory)
	_reload_presenter.configure(_tracker, _materials, _node_factory)
	_combat_event_presenter.configure(_tracker, _materials, _node_factory)
	_interaction_presenter.configure(_tracker, _materials, _node_factory)


func present_result(host: Node, world_root: Node, command_result: Dictionary, world_result: Dictionary) -> Dictionary:
	if host == null or world_root == null:
		return _record_latest({"active": false, "kind": "none", "reason": "presenter_target_missing"})
	var events := _events_from_result(command_result)
	if _result_changes_map(command_result, events):
		return _record_latest({"active": false, "kind": "scene_transition", "event_count": events.size()})
	var movement_cancelled := _movement_presenter.movement_cancelled_presentation(events, world_root, world_result)
	var movement := _movement_presenter.movement_presentation(events, world_root, world_result)
	var interaction := _interaction_presenter.interaction_presentation(events, world_root, world_result)
	if not movement.is_empty() and not interaction.is_empty():
		_movement_presenter.start_movement_tween(host, world_root, movement)
		_interaction_presenter.start_interaction_feedback(host, world_root, interaction)
		return _tracker.latest_snapshot()
	if not movement.is_empty():
		_movement_presenter.start_movement_tween(host, world_root, movement)
		return _tracker.latest_snapshot()
	var attack := _attack_presenter.attack_presentation(events, world_root, world_result)
	if not attack.is_empty():
		var combat_event := _combat_event_presenter.combat_event_presentation(events, world_root, world_result)
		if attack.get("target_node", null) == null and not combat_event.is_empty():
			_combat_event_presenter.start_combat_event_feedback(host, world_root, combat_event)
			return _tracker.latest_snapshot()
		_attack_presenter.start_attack_feedback(host, world_root, attack)
		return _tracker.latest_snapshot()
	if not interaction.is_empty():
		_interaction_presenter.start_interaction_feedback(host, world_root, interaction)
		return _tracker.latest_snapshot()
	var reload := _reload_presenter.reload_presentation(events, world_root, world_result)
	if not reload.is_empty():
		_reload_presenter.start_reload_feedback(host, world_root, reload)
		return _tracker.latest_snapshot()
	var combat_event := _combat_event_presenter.combat_event_presentation(events, world_root, world_result)
	if not combat_event.is_empty():
		_combat_event_presenter.start_combat_event_feedback(host, world_root, combat_event)
		return _tracker.latest_snapshot()
	if not movement_cancelled.is_empty():
		return _record_latest(_movement_presenter.movement_cancelled_public_snapshot(movement_cancelled))
	return _record_latest({"active": false, "kind": "none", "event_count": events.size()})


func snapshot() -> Dictionary:
	return _tracker.snapshot()


func finish_active_presentations() -> Dictionary:
	return _tracker.finish_active_presentations()


func _events_from_result(command_result: Dictionary) -> Array:
	var direct_events := _array_or_empty(command_result.get("events", []))
	if not direct_events.is_empty():
		return direct_events
	var result: Dictionary = _dictionary_or_empty(command_result.get("result", {}))
	var nested_events := _array_or_empty(result.get("events", []))
	if not nested_events.is_empty():
		return nested_events
	var runtime_delta: Dictionary = _dictionary_or_empty(result.get("runtime_snapshot_delta", {}))
	return _array_or_empty(runtime_delta.get("events", []))


func _result_changes_map(command_result: Dictionary, events: Array) -> bool:
	var result: Dictionary = _dictionary_or_empty(command_result.get("result", command_result))
	var context_snapshot: Dictionary = _dictionary_or_empty(result.get("context_snapshot", {}))
	if context_snapshot.has("active_map_id") or context_snapshot.has("active_location_id"):
		return true
	for event_value in events:
		var event: Dictionary = _dictionary_or_empty(event_value)
		var kind := str(event.get("kind", ""))
		if kind == "scene_transition" or kind == "map_changed":
			return true
	return false


func _record_latest(snapshot_data: Dictionary) -> Dictionary:
	return _tracker.record_latest(snapshot_data)


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
