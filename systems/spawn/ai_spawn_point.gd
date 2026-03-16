@tool
class_name AISpawnPoint
extends Marker3D

const GridNavigator = preload("res://systems/grid_navigator.gd")

const CHARACTER_DATA_PATH_TEMPLATE: String = "res://data/characters/%s.json"
const INVALID_CHARACTER_TEXT_TEMPLATE: String = "未设置character_id或者是无效character_id: %s"

const VISUAL_ROOT_NAME: String = "VisualRoot"
const PREVIEW_MESH_NAME: String = "PreviewMesh"
const PREVIEW_LABEL_NAME: String = "PreviewLabel"

const PREVIEW_MESH_POSITION: Vector3 = Vector3(0.0, 0.6, 0.0)
const PREVIEW_LABEL_POSITION: Vector3 = Vector3(0.0, 1.45, 0.0)
const PREVIEW_MESH_SIZE_WORLD: Vector2 = Vector2(0.8, 1.2)
const PREVIEW_LABEL_CHAR_WIDTH_WORLD: float = 0.035
const PREVIEW_LABEL_HEIGHT_WORLD: float = 0.28
const PREVIEW_HIT_PADDING: float = 8.0

const FRIENDLY_PREVIEW_COLOR: Color = Color(0.58, 0.72, 0.88, 1.0)
const TRADER_PREVIEW_COLOR: Color = Color(0.86, 0.73, 0.33, 1.0)
const HOSTILE_PREVIEW_COLOR: Color = Color(0.83, 0.34, 0.31, 1.0)
const INVALID_PREVIEW_COLOR: Color = Color(0.55, 0.55, 0.55, 1.0)

@export var spawn_id: String = ""  # 刷新点唯一ID；为空时使用节点名
@export_custom(PROPERTY_HINT_NONE, "cdc_data_id:character") var character_id: String = ""  # 角色配置ID（Inspector提供下拉和打开编辑器）
@export var auto_spawn: bool = true  # 场景初始化时是否自动生成
@export var respawn_enabled: bool = false  # 角色被移除后是否允许自动重生
@export var respawn_delay: float = 10.0  # 重生延迟（秒）
@export var spawn_radius: float = 0.0  # 随机生成半径（0表示固定在点位中心）

var _refresh_queued: bool = false
var _last_preview_state_key: String = ""
var _visual_root: Node3D = null
var _preview_mesh: MeshInstance3D = null
var _preview_label: Label3D = null

func _enter_tree() -> void:
	if Engine.is_editor_hint():
		set_process(true)
		call_deferred("_apply_editor_defaults")

func _ready() -> void:
	if Engine.is_editor_hint():
		_schedule_preview_refresh()

func _exit_tree() -> void:
	if Engine.is_editor_hint():
		set_process(false)

func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		return

	_snap_marker_to_grid()
	var preview_state_key: String = _build_preview_state_key()
	if preview_state_key != _last_preview_state_key:
		_last_preview_state_key = preview_state_key
		_schedule_preview_refresh()

func _set(property: StringName, value: Variant) -> bool:
	# 兼容历史场景字段 role_id -> character_id
	if String(property) == "role_id":
		character_id = str(value)
		_schedule_preview_refresh()
		return true
	# 历史字段 role_kind 已废弃，读取后直接忽略
	if String(property) == "role_kind":
		return true
	return false

func _get(property: StringName) -> Variant:
	if String(property) == "role_id":
		return character_id
	if String(property) == "role_kind":
		return ""
	return null

func get_effective_spawn_id() -> String:
	if spawn_id.is_empty():
		return name
	return spawn_id

func get_spawn_position() -> Vector3:
	var spawn_origin: Vector3 = _snap_world_pos_to_grid(global_position)
	if spawn_radius <= 0.0:
		return spawn_origin

	var offset: Vector2 = Vector2.RIGHT.rotated(randf() * TAU) * randf_range(0.0, spawn_radius)
	return spawn_origin + Vector3(offset.x, 0.0, offset.y)

func editor_preview_hit_test(camera: Camera3D, screen_pos: Vector2) -> bool:
	if camera == null or not is_inside_tree():
		return false
	if not _ensure_preview_nodes():
		return false

	for rect in _get_editor_preview_screen_rects(camera):
		if rect.has_point(screen_pos):
			return true
	return false

func _apply_editor_defaults() -> void:
	if not Engine.is_editor_hint():
		return
	_ensure_editor_unique_spawn_id()
	_snap_marker_to_grid()
	_last_preview_state_key = _build_preview_state_key()
	_schedule_preview_refresh()

func _build_preview_state_key() -> String:
	return "%s|%s|%s" % [
		spawn_id.strip_edges(),
		character_id.strip_edges(),
		str(global_position)
	]

func _schedule_preview_refresh() -> void:
	if not Engine.is_editor_hint():
		return
	if not is_inside_tree():
		return
	if _refresh_queued:
		return
	_refresh_queued = true
	call_deferred("_refresh_preview")

func _refresh_preview() -> void:
	_refresh_queued = false
	if not Engine.is_editor_hint():
		return
	if not _ensure_preview_nodes():
		return

	var preview_data: Dictionary = _resolve_preview_data()
	_apply_preview_visual(preview_data)

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
	var node_key: String = name.to_snake_case().strip_edges()
	if node_key.is_empty():
		node_key = "spawn_point"
	return "character_%s" % node_key

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

func _ensure_preview_nodes() -> bool:
	_visual_root = get_node_or_null(VISUAL_ROOT_NAME) as Node3D
	if _visual_root == null:
		_visual_root = Node3D.new()
		_visual_root.name = VISUAL_ROOT_NAME
		add_child(_visual_root, false, Node.INTERNAL_MODE_FRONT)
		_visual_root.owner = null

	_preview_mesh = get_node_or_null("%s/%s" % [VISUAL_ROOT_NAME, PREVIEW_MESH_NAME]) as MeshInstance3D
	if _preview_mesh == null and _visual_root != null:
		_preview_mesh = MeshInstance3D.new()
		_preview_mesh.name = PREVIEW_MESH_NAME
		_preview_mesh.position = PREVIEW_MESH_POSITION
		_visual_root.add_child(_preview_mesh, false, Node.INTERNAL_MODE_FRONT)
		_preview_mesh.owner = null

	_preview_label = get_node_or_null(PREVIEW_LABEL_NAME) as Label3D
	if _preview_label == null:
		_preview_label = Label3D.new()
		_preview_label.name = PREVIEW_LABEL_NAME
		_preview_label.position = PREVIEW_LABEL_POSITION
		add_child(_preview_label, false, Node.INTERNAL_MODE_FRONT)
		_preview_label.owner = null

	return _visual_root != null and _preview_mesh != null and _preview_label != null

func _resolve_preview_data() -> Dictionary:
	var normalized_id: String = character_id.strip_edges()
	if normalized_id.is_empty():
		return {
			"is_valid": false,
			"label": _build_invalid_character_text(normalized_id),
			"color": INVALID_PREVIEW_COLOR
		}

	var record: Dictionary = _load_character_record(normalized_id)
	if record.is_empty():
		return {
			"is_valid": false,
			"label": _build_invalid_character_text(normalized_id),
			"color": INVALID_PREVIEW_COLOR
		}

	var display_name: String = str(record.get("name", normalized_id)).strip_edges()
	if display_name.is_empty():
		display_name = normalized_id

	var social: Dictionary = record.get("social", {})
	var title: String = str(social.get("title", "")).strip_edges()
	var label: String = normalized_id
	if not title.is_empty():
		label = "%s | %s %s" % [normalized_id, title, display_name]
	elif display_name != normalized_id:
		label = "%s | %s" % [normalized_id, display_name]

	return {
		"is_valid": true,
		"label": label,
		"color": _resolve_preview_color(record)
	}

func _load_character_record(character_id_text: String) -> Dictionary:
	var data_manager := get_node_or_null("/root/DataManager")
	if data_manager != null and data_manager.has_method("get_character"):
		var runtime_data: Variant = data_manager.get_character(character_id_text)
		if runtime_data is Dictionary and not (runtime_data as Dictionary).is_empty():
			return (runtime_data as Dictionary).duplicate(true)

	var file_path: String = CHARACTER_DATA_PATH_TEMPLATE % character_id_text
	if not FileAccess.file_exists(file_path):
		return {}

	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(file_path))
	if parsed is Dictionary:
		return (parsed as Dictionary).duplicate(true)
	return {}

func _resolve_preview_color(record: Dictionary) -> Color:
	var identity: Dictionary = record.get("identity", {})
	var camp_id: String = str(identity.get("camp_id", "")).strip_edges().to_lower()
	if camp_id == "infected" or camp_id == "raider":
		return HOSTILE_PREVIEW_COLOR

	var visual: Dictionary = record.get("visual", {})
	var placeholder: Dictionary = visual.get("placeholder", {})
	var body_color_text: String = str(placeholder.get("body_color", "")).strip_edges()
	if not body_color_text.is_empty():
		return Color.from_string(body_color_text, FRIENDLY_PREVIEW_COLOR)
	return FRIENDLY_PREVIEW_COLOR

func _apply_preview_visual(preview_data: Dictionary) -> void:
	if _preview_mesh == null or _preview_label == null:
		return

	var color: Color = preview_data.get("color", INVALID_PREVIEW_COLOR)
	var mesh := _preview_mesh.mesh as CapsuleMesh
	if mesh == null:
		mesh = CapsuleMesh.new()
		mesh.radius = 0.22
		mesh.mid_height = 0.55
		_preview_mesh.mesh = mesh

	var material := _preview_mesh.material_override as StandardMaterial3D
	if material == null:
		material = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_preview_mesh.material_override = material
	_preview_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_preview_mesh.visible = true

	_preview_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_preview_label.font_size = 28
	_preview_label.modulate = Color(1.0, 1.0, 1.0, 1.0)
	_preview_label.no_depth_test = false
	_preview_label.text = str(preview_data.get("label", character_id))
	_preview_label.visible = true

func _get_editor_preview_screen_rects(camera: Camera3D) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	if _preview_mesh != null and _preview_mesh.visible:
		var mesh_rect: Rect2 = _build_billboard_screen_rect(
			camera,
			_preview_mesh.global_position,
			PREVIEW_MESH_SIZE_WORLD
		)
		if mesh_rect.size != Vector2.ZERO:
			rects.append(mesh_rect)

	if _preview_label != null and _preview_label.visible:
		var label_text: String = _preview_label.text.strip_edges()
		var label_width_world: float = maxf(0.45, float(label_text.length()) * PREVIEW_LABEL_CHAR_WIDTH_WORLD)
		var label_rect: Rect2 = _build_billboard_screen_rect(
			camera,
			_preview_label.global_position,
			Vector2(label_width_world, PREVIEW_LABEL_HEIGHT_WORLD)
		)
		if label_rect.size != Vector2.ZERO:
			rects.append(label_rect)

	return rects

func _build_billboard_screen_rect(camera: Camera3D, center_world_pos: Vector3, size_world: Vector2) -> Rect2:
	var camera_basis: Basis = camera.global_transform.basis
	var right: Vector3 = camera_basis.x.normalized() * (size_world.x * 0.5)
	var up: Vector3 = camera_basis.y.normalized() * (size_world.y * 0.5)
	var world_points := PackedVector3Array([
		center_world_pos - right - up,
		center_world_pos + right - up,
		center_world_pos + right + up,
		center_world_pos - right + up
	])
	return _build_screen_rect_from_world_points(camera, world_points)

func _build_screen_rect_from_world_points(camera: Camera3D, world_points: PackedVector3Array) -> Rect2:
	if world_points.is_empty():
		return Rect2()

	var min_screen: Vector2 = Vector2(INF, INF)
	var max_screen: Vector2 = Vector2(-INF, -INF)
	var has_visible_point: bool = false
	for world_point in world_points:
		if camera.is_position_behind(world_point):
			continue
		var screen_point: Vector2 = camera.unproject_position(world_point)
		min_screen.x = minf(min_screen.x, screen_point.x)
		min_screen.y = minf(min_screen.y, screen_point.y)
		max_screen.x = maxf(max_screen.x, screen_point.x)
		max_screen.y = maxf(max_screen.y, screen_point.y)
		has_visible_point = true

	if not has_visible_point:
		return Rect2()

	min_screen -= Vector2.ONE * PREVIEW_HIT_PADDING
	max_screen += Vector2.ONE * PREVIEW_HIT_PADDING
	return Rect2(min_screen, max_screen - min_screen)

func _snap_marker_to_grid() -> void:
	if not is_inside_tree():
		return

	var snapped_world_pos: Vector3 = _snap_world_pos_to_grid(global_position)
	if global_position.is_equal_approx(snapped_world_pos):
		return
	global_position = snapped_world_pos

func _snap_world_pos_to_grid(world_pos: Vector3) -> Vector3:
	var grid_size: float = GridNavigator.GRID_SIZE
	return Vector3(
		floor(world_pos.x / grid_size) * grid_size + grid_size * 0.5,
		world_pos.y,
		floor(world_pos.z / grid_size) * grid_size + grid_size * 0.5
	)

func _build_invalid_character_text(raw_character_id: String) -> String:
	return INVALID_CHARACTER_TEXT_TEMPLATE % raw_character_id
