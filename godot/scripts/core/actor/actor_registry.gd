extends RefCounted

const ActorRecord = preload("res://scripts/core/actor/actor_record.gd")

var _next_actor_id: int = 1
var _records: Dictionary = {}
var _registration_order: Array[int] = []


func register_actor(request: Dictionary) -> ActorRecord:
	var record := ActorRecord.new()
	record.actor_id = _next_actor_id
	_next_actor_id += 1

	record.definition_id = str(request.get("definition_id", ""))
	record.display_name = str(request.get("display_name", record.definition_id))
	record.kind = str(request.get("kind", "npc"))
	record.side = str(request.get("side", "neutral"))
	record.group_id = str(request.get("group_id", "neutral"))
	record.registration_index = _registration_order.size()
	record.ap = float(request.get("ap", 0.0))
	record.turn_open = bool(request.get("turn_open", false))
	record.in_combat = bool(request.get("in_combat", false))
	record.grid_position = request.get("grid_position")

	_records[record.actor_id] = record
	_registration_order.append(record.actor_id)
	return record


func get_actor(actor_id: int) -> ActorRecord:
	return _records.get(actor_id)


func require_actor(actor_id: int) -> ActorRecord:
	var record: ActorRecord = get_actor(actor_id)
	if record == null:
		push_error("unknown actor id: %d" % actor_id)
	return record


func actors() -> Array[ActorRecord]:
	var output: Array[ActorRecord] = []
	for actor_id in _registration_order:
		output.append(_records[actor_id])
	return output


func snapshot() -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for record in actors():
		output.append(record.to_dictionary())
	return output
