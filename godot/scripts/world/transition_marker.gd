@tool
class_name TransitionMarker
extends Node3D

const GATE_PILLAR_SCENE := preload("res://assets/world_tiles/prop_placeholder_basic/gate_pillar_concrete.gltf")
const ROADBLOCK_SCENE := preload("res://assets/world_tiles/prop_placeholder_basic/roadblock_concrete.gltf")
const SANDBAG_SCENE := preload("res://assets/world_tiles/prop_placeholder_basic/sandbag_barrier.gltf")
const WALL_STRAIGHT_SCENE := preload("res://assets/world_tiles/building_wall/straight.gltf")

@export_enum("subscene", "outdoor", "overworld") var marker_kind: String = "overworld":
	set(value):
		marker_kind = value
		_rebuild_marker()
@export var footprint: Vector2i = Vector2i.ONE:
	set(value):
		footprint = Vector2i(max(1, value.x), max(1, value.y))
		_rebuild_marker()


func _ready() -> void:
	_rebuild_marker()


func _rebuild_marker() -> void:
	if not is_inside_tree():
		return
	for child in get_children():
		child.free()

	match marker_kind:
		"subscene":
			_build_subscene_marker()
		"outdoor":
			_build_outdoor_marker()
		_:
			_build_overworld_marker()


func _build_subscene_marker() -> void:
	var left := _instance_scene(GATE_PILLAR_SCENE, "LeftPillar", Vector3(-0.42, 0.0, 0.0), Vector3(0.65, 0.9, 0.65))
	var right := _instance_scene(GATE_PILLAR_SCENE, "RightPillar", Vector3(0.42, 0.0, 0.0), Vector3(0.65, 0.9, 0.65))
	var lintel := _instance_scene(WALL_STRAIGHT_SCENE, "Lintel", Vector3(0.0, 1.25, 0.0), Vector3(0.95, 0.35, 0.28))
	lintel.rotation_degrees = Vector3(0.0, 90.0, 0.0)
	_add_threshold(Vector3(0.0, 0.02, 0.0), Vector3(1.1, 0.04, 0.32), Color(0.52, 0.42, 0.30, 1.0))
	_tag_marker_node(left)
	_tag_marker_node(right)
	_tag_marker_node(lintel)


func _build_outdoor_marker() -> void:
	var half_span: float = max(1.0, float(footprint.y) * 0.5) * 0.45
	var left := _instance_scene(GATE_PILLAR_SCENE, "LeftGatePillar", Vector3(0.0, 0.0, -half_span), Vector3(0.75, 1.0, 0.75))
	var right := _instance_scene(GATE_PILLAR_SCENE, "RightGatePillar", Vector3(0.0, 0.0, half_span), Vector3(0.75, 1.0, 0.75))
	var barrier := _instance_scene(SANDBAG_SCENE, "GateBarrier", Vector3(0.15, 0.0, 0.0), Vector3(0.9, 0.9, min(1.8, max(0.75, float(footprint.y) * 0.24))))
	barrier.rotation_degrees = Vector3(0.0, 90.0, 0.0)
	_add_threshold(Vector3(0.0, 0.025, 0.0), Vector3(0.12, 0.05, max(1.1, float(footprint.y) * 0.86)), Color(0.42, 0.38, 0.30, 1.0))
	_tag_marker_node(left)
	_tag_marker_node(right)
	_tag_marker_node(barrier)


func _build_overworld_marker() -> void:
	var base := _instance_scene(ROADBLOCK_SCENE, "ExitRoadblock", Vector3(0.0, 0.0, 0.0), Vector3(0.78, 0.78, 0.78))
	var post := _instance_scene(GATE_PILLAR_SCENE, "ExitPost", Vector3(-0.36, 0.0, -0.18), Vector3(0.42, 0.72, 0.42))
	var sign := _add_box("ExitSign", Vector3(0.48, 0.24, 0.06), Vector3(-0.36, 0.78, -0.18), Color(0.78, 0.68, 0.42, 1.0))
	_add_threshold(Vector3(0.0, 0.018, 0.0), Vector3(0.74, 0.035, 0.74), Color(0.34, 0.37, 0.32, 1.0))
	_tag_marker_node(base)
	_tag_marker_node(post)
	_tag_marker_node(sign)


func _instance_scene(scene: PackedScene, node_name: String, node_position: Vector3, node_scale: Vector3) -> Node3D:
	var node := scene.instantiate() as Node3D
	node.name = node_name
	node.position = node_position
	node.scale = node_scale
	add_child(node)
	_tag_marker_node(node)
	return node


func _add_threshold(node_position: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var node := _add_box("EntryThreshold", size, node_position, color)
	node.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	return node


func _add_box(node_name: String, size: Vector3, node_position: Vector3, color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.86
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	node.material_override = material
	node.position = node_position
	add_child(node)
	_tag_marker_node(node)
	return node


func _tag_marker_node(node: Node) -> void:
	node.set_meta("transition_marker", true)
	node.set_meta("transition_marker_kind", marker_kind)
