extends RefCounted

var kind: String
var payload: Dictionary


func _init(p_kind: String = "", p_payload: Dictionary = {}) -> void:
	kind = p_kind
	payload = p_payload


func to_dictionary() -> Dictionary:
	return {
		"kind": kind,
		"payload": payload,
	}
