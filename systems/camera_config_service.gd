extends Node

signal config_changed
const CameraConfig3DScript = preload("res://systems/camera_config_3d.gd")
const DEFAULT_CONFIG_PATH: String = "res://config/camera/default_camera_3d.tres"
const _OVERRIDABLE_KEYS: Array[String] = [
	"projection_type",
	"rotation",
	"viewpoint_offset",
	"arm_length",
	"min_zoom",
	"max_zoom",
	"initial_zoom",
	"min_fov",
	"max_fov",
	"initial_fov",
	"zoom_speed",
	"zoom_smoothing",
	"follow_smoothing"
]

var _base_config: Resource = null
var _effective_config: Resource = null
var _runtime_override: Dictionary = {}

func _ready() -> void:
	_base_config = _load_base_config()
	_rebuild_effective_config()

func get_effective_config() -> Resource:
	if not _effective_config:
		_rebuild_effective_config()
	return _effective_config.duplicate(true)

func set_runtime_override(override_values: Dictionary) -> void:
	_runtime_override.clear()
	for key_variant in override_values.keys():
		var key := str(key_variant)
		if not _OVERRIDABLE_KEYS.has(key):
			continue
		_runtime_override[key] = override_values[key_variant]
	_rebuild_effective_config()
	config_changed.emit()

func clear_runtime_override() -> void:
	if _runtime_override.is_empty():
		return
	_runtime_override.clear()
	_rebuild_effective_config()
	config_changed.emit()

func _load_base_config() -> Resource:
	var loaded: Resource = load(DEFAULT_CONFIG_PATH)
	if loaded and loaded is CameraConfig3DScript:
		return loaded
	push_error("CameraConfigService: Failed to load %s, using in-memory defaults" % DEFAULT_CONFIG_PATH)
	return CameraConfig3DScript.new()

func _rebuild_effective_config() -> void:
	if not _base_config:
		_base_config = CameraConfig3DScript.new()
	_effective_config = _base_config.duplicate(true)
	_apply_runtime_override(_effective_config)
	_sanitize_config(_effective_config)

func _apply_runtime_override(config: Resource) -> void:
	for key in _runtime_override.keys():
		var value: Variant = _runtime_override[key]
		match key:
			"projection_type":
				config.projection_type = _to_projection_type(value, config.projection_type)
			"rotation":
				config.rotation = _to_vector3(value, config.rotation)
			"viewpoint_offset":
				config.viewpoint_offset = _to_vector3(value, config.viewpoint_offset)
			"arm_length":
				config.arm_length = _to_float(value, config.arm_length)
			"min_zoom":
				config.min_zoom = _to_float(value, config.min_zoom)
			"max_zoom":
				config.max_zoom = _to_float(value, config.max_zoom)
			"initial_zoom":
				config.initial_zoom = _to_float(value, config.initial_zoom)
			"min_fov":
				config.min_fov = _to_float(value, config.min_fov)
			"max_fov":
				config.max_fov = _to_float(value, config.max_fov)
			"initial_fov":
				config.initial_fov = _to_float(value, config.initial_fov)
			"zoom_speed":
				config.zoom_speed = _to_float(value, config.zoom_speed)
			"zoom_smoothing":
				config.zoom_smoothing = _to_float(value, config.zoom_smoothing)
			"follow_smoothing":
				config.follow_smoothing = _to_float(value, config.follow_smoothing)

func _sanitize_config(config: Resource) -> void:
	if config.min_zoom > config.max_zoom:
		var tmp_zoom: float = config.min_zoom
		config.min_zoom = config.max_zoom
		config.max_zoom = tmp_zoom
	if config.min_fov > config.max_fov:
		var tmp_fov: float = config.min_fov
		config.min_fov = config.max_fov
		config.max_fov = tmp_fov
	config.initial_zoom = clamp(config.initial_zoom, config.min_zoom, config.max_zoom)
	config.initial_fov = clamp(config.initial_fov, config.min_fov, config.max_fov)
	config.arm_length = maxf(config.arm_length, 0.01)
	config.zoom_speed = maxf(config.zoom_speed, 0.01)
	config.zoom_smoothing = clamp(config.zoom_smoothing, 0.01, 1.0)
	config.follow_smoothing = clamp(config.follow_smoothing, 0.01, 1.0)
	config.projection_type = clampi(config.projection_type, CameraConfig3DScript.ProjectionType.ORTHOGRAPHIC, CameraConfig3DScript.ProjectionType.PERSPECTIVE)

func _to_projection_type(value: Variant, fallback: int) -> int:
	if value is int:
		return clampi(value, CameraConfig3DScript.ProjectionType.ORTHOGRAPHIC, CameraConfig3DScript.ProjectionType.PERSPECTIVE)
	var text := str(value).to_lower().strip_edges()
	if text in ["orthographic", "ortho", "0"]:
		return CameraConfig3DScript.ProjectionType.ORTHOGRAPHIC
	if text in ["perspective", "persp", "1"]:
		return CameraConfig3DScript.ProjectionType.PERSPECTIVE
	return fallback

func _to_float(value: Variant, fallback: float) -> float:
	if value is float or value is int:
		return float(value)
	var text := str(value).strip_edges()
	if text.is_valid_float():
		return text.to_float()
	return fallback

func _to_vector3(value: Variant, fallback: Vector3) -> Vector3:
	if value is Vector3:
		return value
	return fallback
