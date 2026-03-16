class_name HoverOutline3D
extends Node3D

const OUTLINE_MESH_MATERIAL_TRANSPARENCY: BaseMaterial3D.Transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

@export var target_root_path: NodePath = NodePath("..")
@export var target_node_paths: Array[NodePath] = []
@export var outline_scale: float = 1.06
@export var outline_depth_offset: float = -0.001

var _outline_root: Node3D = null
var _hover_outline_visible: bool = false
var _hover_outline_color: Color = Color(1.0, 1.0, 1.0, 1.0)

func _ready() -> void:
	_ensure_outline_root()
	_apply_hover_outline_visibility()

func set_hover_outline_visible(visible: bool) -> void:
	_hover_outline_visible = visible
	if visible:
		_rebuild_outline_nodes()
	_apply_hover_outline_visibility()

func set_hover_outline_color(color: Color) -> void:
	if _hover_outline_color == color:
		return
	_hover_outline_color = color
	if _hover_outline_visible:
		_rebuild_outline_nodes()

func _ensure_outline_root() -> void:
	_outline_root = get_node_or_null("OutlineRoot") as Node3D
	if _outline_root != null:
		return
	_outline_root = Node3D.new()
	_outline_root.name = "OutlineRoot"
	add_child(_outline_root)

func _apply_hover_outline_visibility() -> void:
	if _outline_root != null:
		_outline_root.visible = _hover_outline_visible

func _rebuild_outline_nodes() -> void:
	_ensure_outline_root()
	for child in _outline_root.get_children():
		_outline_root.remove_child(child)
		child.queue_free()

	for target in _resolve_outline_targets():
		var outline_node := _duplicate_outline_node(target)
		if outline_node == null:
			continue
		outline_node.transform = global_transform.affine_inverse() * target.global_transform
		outline_node.position += Vector3(0.0, 0.0, outline_depth_offset)
		outline_node.scale *= outline_scale
		_apply_outline_style(outline_node)
		_outline_root.add_child(outline_node)

func _resolve_outline_targets() -> Array[Node3D]:
	var targets: Array[Node3D] = []
	if not target_node_paths.is_empty():
		for target_path in target_node_paths:
			var explicit_target := get_node_or_null(target_path)
			if explicit_target == null:
				continue
			if _is_supported_outline_target(explicit_target):
				targets.append(explicit_target as Node3D)
				continue
			_collect_outline_targets(explicit_target, targets)
		return targets

	var target_root: Node = get_node_or_null(target_root_path)
	if target_root == null:
		target_root = get_parent()
	_collect_outline_targets(target_root, targets)
	return targets

func _collect_outline_targets(node: Node, targets: Array[Node3D]) -> void:
	if node == null or node == self or node == _outline_root:
		return
	if _is_supported_outline_target(node):
		targets.append(node as Node3D)
		return
	for child in node.get_children():
		_collect_outline_targets(child, targets)

func _is_supported_outline_target(node: Node) -> bool:
	if node == null or not (node is Node3D):
		return false
	return node is MeshInstance3D or node is Sprite3D or node is Label3D

func _duplicate_outline_node(target: Node3D) -> Node3D:
	var duplicate_node := target.duplicate(0) as Node3D
	if duplicate_node == null:
		return null
	for child in duplicate_node.get_children():
		duplicate_node.remove_child(child)
		child.queue_free()
	duplicate_node.name = "%sOutline" % target.name
	return duplicate_node

func _apply_outline_style(outline_node: Node3D) -> void:
	if outline_node is MeshInstance3D:
		var outline_mesh := outline_node as MeshInstance3D
		outline_mesh.material_override = _build_outline_material()
	elif outline_node is Sprite3D:
		var outline_sprite := outline_node as Sprite3D
		outline_sprite.modulate = _hover_outline_color
	elif outline_node is Label3D:
		var outline_label := outline_node as Label3D
		outline_label.modulate = _hover_outline_color

	if outline_node is GeometryInstance3D:
		var geometry := outline_node as GeometryInstance3D
		geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _build_outline_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = OUTLINE_MESH_MATERIAL_TRANSPARENCY
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = _hover_outline_color
	material.no_depth_test = false
	return material
