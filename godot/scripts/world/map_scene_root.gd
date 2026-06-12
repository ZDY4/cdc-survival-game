@tool
class_name MapSceneRoot
extends Node3D

const MapEntryPointNodeScript = preload("res://scripts/world/map_entry_point_node.gd")
const MapObjectNodeScript = preload("res://scripts/world/map_object_node.gd")
const GAME_ROOT_SCENE_PATH := "res://scenes/game/game_root.tscn"
const MAP_ENTRY_POINT_GROUP := "map_entry_point"
const MAP_SCENE_OBJECT_GROUP := "map_scene_object"

@export var map_id: String = ""
@export var map_name: String = ""
@export var map_size: Vector2i = Vector2i.ONE
@export var default_level: int = 0


func _ready() -> void:
	if _should_redirect_direct_runtime_launch():
		call_deferred("_redirect_direct_runtime_launch")


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
		if _is_map_entry_point(child):
			var entry: Dictionary = child.call("to_entry_definition")
			if not str(entry.get("id", "")).is_empty():
				entry_points.append(entry)
		elif _is_map_scene_object(child):
			var object: Dictionary = child.call("to_object_definition")
			if not str(object.get("object_id", "")).is_empty():
				objects.append(object)
		_collect_map_nodes(child, entry_points, objects)


func _is_map_entry_point(node: Node) -> bool:
	if node.is_in_group(MAP_ENTRY_POINT_GROUP) and node.has_method("to_entry_definition"):
		return true
	if node.has_method("to_entry_definition"):
		return true
	return node.get_script() == MapEntryPointNodeScript


func _is_map_scene_object(node: Node) -> bool:
	if node.is_in_group(MAP_SCENE_OBJECT_GROUP) and node.has_method("to_object_definition"):
		return true
	if node.has_method("to_object_definition"):
		return true
	return node.get_script() == MapObjectNodeScript


func _should_redirect_direct_runtime_launch() -> bool:
	return not Engine.is_editor_hint() and get_tree() != null and get_tree().current_scene == self


func _redirect_direct_runtime_launch() -> void:
	var error := get_tree().change_scene_to_file(GAME_ROOT_SCENE_PATH)
	if error != OK:
		push_error("地图场景不能单独作为游戏运行入口，切换 GameRoot 失败: %s" % GAME_ROOT_SCENE_PATH)
