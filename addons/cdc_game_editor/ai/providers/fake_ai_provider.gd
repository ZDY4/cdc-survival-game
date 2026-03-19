@tool
extends Node

var next_response: Dictionary = {}
var response_queue: Array[Dictionary] = []


func enqueue_response(response: Dictionary) -> void:
	response_queue.append(response.duplicate(true))


func generate_request(_payload: Dictionary) -> Dictionary:
	await Engine.get_main_loop().process_frame
	if not response_queue.is_empty():
		return response_queue.pop_front()
	if not next_response.is_empty():
		return next_response.duplicate(true)
	return {
		"ok": false,
		"error": "Fake provider has no queued response"
	}


func test_connection(_config: Dictionary) -> Dictionary:
	return {"ok": true, "data": {"message": "fake-ok"}}
