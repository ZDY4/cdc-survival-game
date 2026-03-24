@tool
extends StaticBody3D
## Reusable drag-and-drop pickup object for 3D scenes.
## LEGACY AUTHORITY BOUNDARY:
## This node should remain a Godot presentation/placement shell for pickups.
## Avoid expanding authoritative inventory transfer logic here; keep authority
## migration moving toward shared Rust runtime/protocol paths.

const ItemIdResolver = preload("res://core/item_id_resolver.gd")
const InteractableScript = preload("res://modules/interaction/interactable.gd")
const PickupInteractionOptionScript = preload("res://modules/interaction/options/pickup_interaction_option.gd")

# 1. Constants
const INVALID_ITEM_TEXT: String = "未设置 item_id"
const PICKUP_ROOT_PATH: NodePath = NodePath("..")
const DEFAULT_ICON_HEIGHT: float = 0.9
const MIN_ICON_WIDTH: float = 0.45
const MAX_ICON_WIDTH: float = 1.2

# 2. Exports
@export_custom(PROPERTY_HINT_NONE, "cdc_data_id:item") var item_id: String = "":
	set(value):
		item_id = value
		_schedule_refresh()
@export var min_count: int = 1:
	set(value):
		min_count = max(1, value)
		_schedule_refresh()
@export var max_count: int = 1:
	set(value):
		max_count = max(1, value)
		_schedule_refresh()

# 3. Public variables
@onready var _visual_root: Node3D = get_node_or_null("VisualRoot") as Node3D
@onready var _icon_mesh: MeshInstance3D = get_node_or_null("VisualRoot/IconMesh") as MeshInstance3D
@onready var _fallback_label: Label3D = get_node_or_null("FallbackLabel") as Label3D
@onready var _interactable: Node = get_node_or_null("Interactable") as Node

# 4. Private variables
var _refresh_queued: bool = false
var _dynamic_visual: Node3D = null
var _explicit_interaction_name: String = ""
var _last_generated_interaction_name: String = ""

func _ready() -> void:
	_cache_explicit_interaction_name()
	_schedule_refresh()

# 6. Public methods
func refresh_from_item_data() -> void:
	_refresh_pickup()

func get_damage_feedback_anchor() -> Node3D:
	return _visual_root

func get_hit_reaction_target() -> Node3D:
	return _visual_root

# 7. Private methods
func _schedule_refresh() -> void:
	if not is_inside_tree():
		return
	if _refresh_queued:
		return
	_refresh_queued = true
	call_deferred("_refresh_pickup")

func _refresh_pickup() -> void:
	_refresh_queued = false
	if not _has_required_nodes():
		return

	_cache_explicit_interaction_name()
	var item_state: Dictionary = _resolve_item_state()
	_apply_pickup_option(item_state)
	_apply_visual_state(item_state)

func _apply_pickup_option(item_state: Dictionary) -> void:
	if _interactable == null:
		return

	var pickup_option: Resource = PickupInteractionOptionScript.new()
	var resolved_item_id: String = str(item_state.get("resolved_item_id", ""))
	pickup_option.item_id = resolved_item_id
	pickup_option.min_count = max(1, min(min_count, max_count))
	pickup_option.max_count = max(pickup_option.min_count, max(min_count, max_count))
	pickup_option.pickup_root_path = PICKUP_ROOT_PATH

	# Interactable is not a tool script, so the editor only has a placeholder
	# instance for it. Skip runtime option wiring while previewing in-editor.
	if not Engine.is_editor_hint():
		_interactable.set_options([pickup_option])
	_set_generated_interaction_name(_build_interaction_name(item_state))

func _apply_visual_state(item_state: Dictionary) -> void:
	_clear_dynamic_visual()
	_configure_fallback_label()
	_hide_fallback_label()
	_hide_icon_mesh()

	if not bool(item_state.get("is_valid", false)):
		_show_fallback_label(str(item_state.get("error_text", INVALID_ITEM_TEXT)))
		return

	var item_data: Dictionary = item_state.get("item_data", {}) as Dictionary
	if _try_apply_model_visual(item_data):
		return
	if _try_apply_icon_visual(item_data):
		return
	_show_fallback_label("无可用模型: %s" % str(item_state.get("display_name", item_id)))

func _resolve_item_state() -> Dictionary:
	var raw_item_id: String = str(item_id).strip_edges()
	if raw_item_id.is_empty():
		return {
			"is_valid": false,
			"resolved_item_id": "",
			"display_name": "",
			"item_data": {},
			"error_text": INVALID_ITEM_TEXT
		}

	var resolved_item_id: String = ItemIdResolver.resolve_item_id(raw_item_id)
	var item_data: Dictionary = _load_item_data(raw_item_id, resolved_item_id)
	if item_data.is_empty():
		return {
			"is_valid": false,
			"resolved_item_id": resolved_item_id,
			"display_name": raw_item_id,
			"item_data": {},
			"error_text": "无效 item_id: %s" % raw_item_id
		}

	var display_name: String = str(item_data.get("name", resolved_item_id))
	return {
		"is_valid": true,
		"resolved_item_id": resolved_item_id,
		"display_name": display_name,
		"item_data": item_data,
		"error_text": ""
	}

func _load_item_data(raw_item_id: String, resolved_item_id: String) -> Dictionary:
	if Engine.is_editor_hint():
		var editor_item: Dictionary = ItemIdResolver.load_item_data_from_json(resolved_item_id)
		if not editor_item.is_empty():
			return editor_item
		return ItemIdResolver.load_item_data_from_json(raw_item_id)

	if ItemDatabase and ItemDatabase.has_method("get_item"):
		var runtime_item: Dictionary = ItemDatabase.get_item(resolved_item_id)
		if not runtime_item.is_empty():
			return runtime_item
		runtime_item = ItemDatabase.get_item(raw_item_id)
		if not runtime_item.is_empty():
			return runtime_item
	return ItemIdResolver.load_item_data_from_json(raw_item_id)

func _build_interaction_name(item_state: Dictionary) -> String:
	if bool(item_state.get("is_valid", false)):
		return str(item_state.get("display_name", item_id))
	if not _explicit_interaction_name.is_empty():
		return _explicit_interaction_name
	var raw_item_id: String = str(item_id).strip_edges()
	if not raw_item_id.is_empty():
		return raw_item_id
	return name

func _set_generated_interaction_name(new_name: String) -> void:
	if _interactable == null:
		return
	_last_generated_interaction_name = new_name
	_interactable.interaction_name = new_name

func _cache_explicit_interaction_name() -> void:
	if _interactable == null:
		return
	var current_name: String = _interactable.interaction_name
	if current_name.is_empty():
		return
	if current_name == _last_generated_interaction_name:
		return
	_explicit_interaction_name = current_name

func _try_apply_model_visual(item_data: Dictionary) -> bool:
	var model_path: String = str(item_data.get("model_path", "")).strip_edges()
	if model_path.is_empty():
		return false
	if not ResourceLoader.exists(model_path):
		return false

	var model_resource: Resource = load(model_path)
	if model_resource == null:
		return false

	if model_resource is PackedScene:
		var packed_scene := model_resource as PackedScene
		var instance: Node = packed_scene.instantiate()
		if instance is Node3D:
			_set_dynamic_visual(instance as Node3D)
			return true
		if is_instance_valid(instance):
			instance.queue_free()
		return false

	if model_resource is Mesh:
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.mesh = model_resource as Mesh
		_set_dynamic_visual(mesh_instance)
		return true

	return false

func _try_apply_icon_visual(item_data: Dictionary) -> bool:
	var icon_path: String = str(item_data.get("icon_path", "")).strip_edges()
	var texture_candidates: Array[String] = []
	var generated_texture_path: String = ItemIdResolver.build_generated_texture_path(icon_path)
	if not generated_texture_path.is_empty():
		texture_candidates.append(generated_texture_path)
	if not icon_path.is_empty():
		texture_candidates.append(icon_path)

	var icon_texture: Texture2D = null
	for candidate in texture_candidates:
		if not ResourceLoader.exists(candidate):
			continue
		var resource: Resource = load(candidate)
		if resource is Texture2D:
			icon_texture = resource as Texture2D
			break

	if icon_texture == null:
		return false

	_show_icon_mesh(icon_texture)
	return true

func _show_icon_mesh(icon_texture: Texture2D) -> void:
	if _icon_mesh == null:
		return

	var quad_mesh := _icon_mesh.mesh as QuadMesh
	if quad_mesh == null:
		quad_mesh = QuadMesh.new()
		_icon_mesh.mesh = quad_mesh

	var texture_size: Vector2 = icon_texture.get_size()
	var aspect_ratio: float = 1.0
	if texture_size.y > 0.0:
		aspect_ratio = texture_size.x / texture_size.y
	var icon_width: float = clampf(DEFAULT_ICON_HEIGHT * aspect_ratio, MIN_ICON_WIDTH, MAX_ICON_WIDTH)
	quad_mesh.size = Vector2(icon_width, DEFAULT_ICON_HEIGHT)

	var material := _icon_mesh.get_active_material(0) as StandardMaterial3D
	if material == null:
		material = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_texture = icon_texture
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_icon_mesh.material_override = material
	_icon_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_icon_mesh.visible = true

func _hide_icon_mesh() -> void:
	if _icon_mesh != null:
		_icon_mesh.visible = false

func _set_dynamic_visual(node: Node3D) -> void:
	if _visual_root == null:
		return
	_dynamic_visual = node
	_dynamic_visual.name = "DynamicVisual"
	_dynamic_visual.position = Vector3.ZERO
	_visual_root.add_child(_dynamic_visual)
	_hide_icon_mesh()
	_hide_fallback_label()

func _clear_dynamic_visual() -> void:
	if _visual_root == null:
		return
	for child in _visual_root.get_children():
		if child == _icon_mesh:
			continue
		_visual_root.remove_child(child)
		child.queue_free()
	_dynamic_visual = null

func _configure_fallback_label() -> void:
	if _fallback_label == null:
		return
	_fallback_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_fallback_label.font_size = 32
	_fallback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fallback_label.modulate = Color(1.0, 1.0, 1.0, 1.0)
	_fallback_label.no_depth_test = false

func _show_fallback_label(text: String) -> void:
	if _fallback_label == null:
		return
	_fallback_label.text = text
	_fallback_label.visible = true

func _hide_fallback_label() -> void:
	if _fallback_label != null:
		_fallback_label.visible = false

func _has_required_nodes() -> bool:
	return _visual_root != null and _icon_mesh != null and _fallback_label != null and _interactable != null
