@tool
class_name MapSceneRoot
extends Node3D

const MapEntryPointNodeScript = preload("res://scripts/world/map_entry_point_node.gd")
const MapObjectNodeScript = preload("res://scripts/world/map_object_node.gd")

@export var map_id: String = ""
@export var map_name: String = ""
@export var map_size: Vector2i = Vector2i.ONE
@export var default_level: int = 0


func to_definition() -> Dictionary:
	var entry_points: Array[Dictionary] = []
	var objects: Array[Dictionary] = []
	_collect_map_nodes(self, entry_points, objects)
	return {
		"id": map_id,
		"name": map_name,
		"size": {
			"width": max(1, map_size.x),
			"height": max(1, map_size.y),
		},
		"default_level": default_level,
		"levels": [
			{
				"y": default_level,
				"cells": [],
			},
		],
		"entry_points": entry_points,
		"objects": objects,
	}


func _collect_map_nodes(node: Node, entry_points: Array[Dictionary], objects: Array[Dictionary]) -> void:
	for child in node.get_children():
		var child_script: Variant = child.get_script()
		if child_script == MapEntryPointNodeScript:
			var entry: Dictionary = child.to_entry_definition()
			if not str(entry.get("id", "")).is_empty():
				entry_points.append(entry)
		elif child_script == MapObjectNodeScript:
			var object: Dictionary = child.to_object_definition()
			if not str(object.get("object_id", "")).is_empty():
				objects.append(object)
		_collect_map_nodes(child, entry_points, objects)
