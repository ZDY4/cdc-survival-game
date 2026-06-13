class_name WorldMarkerLayer
extends Node3D


func sync_markers(_actor_layer: Node, _corpse_layer: Node, _world_snapshot: Dictionary, _runtime_snapshot: Dictionary = {}) -> Dictionary:
	return {"count": get_child_count()}


func clear_markers() -> void:
	for child in get_children():
		child.queue_free()
