@tool
class_name AISpawnPoint
extends Marker3D

@export var spawn_id: String = ""  # 刷新点唯一ID；为空时使用节点名
@export_enum("npc", "enemy") var role_kind: String = "npc"  # 生成角色类型：npc 或 enemy
@export_custom(PROPERTY_HINT_NONE, "cdc_data_id:character") var character_id: String = ""  # 角色配置ID（Inspector提供下拉和打开编辑器）
@export var auto_spawn: bool = true  # 场景初始化时是否自动生成
@export var respawn_enabled: bool = false  # 角色被移除后是否允许自动重生
@export var respawn_delay: float = 10.0  # 重生延迟（秒）
@export var spawn_radius: float = 0.0  # 随机生成半径（0表示固定在点位中心）

func _enter_tree() -> void:
	if Engine.is_editor_hint():
		call_deferred("_ensure_editor_unique_spawn_id")

func _set(property: StringName, value: Variant) -> bool:
	# 兼容历史场景字段 role_id -> character_id
	if String(property) == "role_id":
		character_id = str(value)
		return true
	return false

func _get(property: StringName) -> Variant:
	# 兼容历史场景字段 role_id -> character_id
	if String(property) == "role_id":
		return character_id
	return null

func get_effective_spawn_id() -> String:
	if spawn_id.is_empty():
		return name
	return spawn_id

func get_spawn_position() -> Vector3:
	if spawn_radius <= 0.0:
		return global_position

	var offset := Vector2.RIGHT.rotated(randf() * TAU) * randf_range(0.0, spawn_radius)
	return global_position + Vector3(offset.x, 0.0, offset.y)

func _ensure_editor_unique_spawn_id() -> void:
	if not Engine.is_editor_hint():
		return
	if not is_inside_tree():
		return

	var current_id: String = spawn_id.strip_edges()
	if current_id.is_empty() or _is_spawn_id_taken(current_id):
		spawn_id = _generate_unique_spawn_id()

func _generate_unique_spawn_id() -> String:
	var base_name: String = _build_spawn_id_base()
	var candidate: String = base_name
	var suffix: int = 1
	while _is_spawn_id_taken(candidate):
		candidate = "%s_%02d" % [base_name, suffix]
		suffix += 1
	return candidate

func _build_spawn_id_base() -> String:
	var kind: String = role_kind.strip_edges().to_lower()
	if kind.is_empty():
		kind = "role"
	var node_key: String = name.to_snake_case().strip_edges()
	if node_key.is_empty():
		node_key = "spawn_point"
	return "%s_%s" % [kind, node_key]

func _is_spawn_id_taken(candidate_id: String) -> bool:
	var scene_root: Node = _get_scene_root_for_scan()
	if not scene_root:
		return false

	for point in _collect_spawn_points(scene_root):
		if point == self:
			continue
		if point.get_effective_spawn_id() == candidate_id:
			return true
	return false

func _get_scene_root_for_scan() -> Node:
	var tree: SceneTree = get_tree()
	if not tree:
		return null
	if tree.edited_scene_root:
		return tree.edited_scene_root
	return tree.current_scene

func _collect_spawn_points(root: Node) -> Array[AISpawnPoint]:
	var result: Array[AISpawnPoint] = []
	for child in root.get_children():
		if child is AISpawnPoint:
			result.append(child)
		result.append_array(_collect_spawn_points(child))
	return result
