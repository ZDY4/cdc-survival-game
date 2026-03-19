class_name AbilityTargetingSystem
extends Node

const GridAreaOverlay = preload("res://systems/grid_area_overlay.gd")

signal targeting_started(session: Dictionary)
signal targeting_confirmed(result: Dictionary)
signal targeting_cancelled(session: Dictionary, reason: String)
signal preview_updated(preview: Dictionary)

var _session: Dictionary = {}
var _preview: Dictionary = {}
var _overlay: GridAreaOverlay = null


func _process(_delta: float) -> void:
	if not is_targeting():
		return
	_refresh_preview_from_pointer()


func is_targeting() -> bool:
	return not _session.is_empty()


func get_session() -> Dictionary:
	return _session.duplicate(true)


func get_current_preview() -> Dictionary:
	return _preview.duplicate(true)


func begin_skill_targeting(skill_id: String, handler: TargetAbilityBase, context: Dictionary) -> Dictionary:
	var targeting_context: Dictionary = context.duplicate(true)
	targeting_context["skill_id"] = skill_id
	var session: Dictionary = handler.begin_targeting(targeting_context)
	return begin_session(session)


func begin_attack_targeting(handler: TargetAbilityBase, context: Dictionary) -> Dictionary:
	var session: Dictionary = handler.begin_targeting(context)
	return begin_session(session)


func begin_session(session: Dictionary) -> Dictionary:
	var handler: TargetAbilityBase = session.get("handler", null) as TargetAbilityBase
	if handler == null:
		return {"success": false, "reason": "missing_handler"}

	if is_targeting():
		cancel_targeting("replaced")

	_session = {
		"success": bool(session.get("success", true)),
		"state": str(session.get("state", "targeting_started")),
		"ability_kind": str(session.get("ability_kind", "")),
		"ability_id": str(session.get("ability_id", "")),
		"handler": handler,
		"context": (session.get("context", {}) as Dictionary).duplicate(true)
	}
	_preview.clear()
	_prepare_caster_for_targeting()
	_ensure_overlay_attached()
	set_process(true)
	_refresh_preview_from_pointer(true)
	if _preview.is_empty():
		_refresh_preview_from_preferred_cell()
	targeting_started.emit(get_session())
	return {
		"success": true,
		"state": "targeting_started",
		"session": get_session()
	}


func cancel_targeting(reason: String = "cancelled") -> void:
	if not is_targeting():
		return
	var previous_session: Dictionary = get_session()
	_notify_targeting_cancelled(previous_session, reason)
	_clear_session()
	targeting_cancelled.emit(previous_session, reason)


func handle_input(event: InputEvent) -> bool:
	if not is_targeting():
		return false

	if event is InputEventMouseMotion:
		_refresh_preview_from_pointer()
		return true

	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event == null:
			return false
		if mouse_event.button_index == MOUSE_BUTTON_RIGHT and mouse_event.pressed:
			cancel_targeting("cancelled")
			return true
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			if _is_pointer_over_blocking_ui():
				return true
			if _preview.is_empty() or not bool(_preview.get("valid", false)):
				return true
			_confirm_current_preview()
			return true
		return false

	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event != null and key_event.pressed and not key_event.echo and key_event.keycode == KEY_ESCAPE:
			cancel_targeting("cancelled")
			return true

	return false


func handle_hotbar_slot_activation(slot_index: int) -> bool:
	if not is_targeting():
		return false
	var context: Dictionary = _get_session_context()
	return _cancel_if_same_slot(slot_index, context)


func handle_attack_activation() -> bool:
	if not is_targeting():
		return false
	if str(_session.get("ability_kind", "")) != "attack":
		return false
	cancel_targeting("cancelled")
	return true


func owns_control(control: Control) -> bool:
	return _overlay != null and _overlay.owns_control(control)


func _cancel_if_same_slot(slot_index: int, context: Dictionary) -> bool:
	if str(_session.get("ability_kind", "")) != "skill":
		return false
	if int(context.get("slot_index", -1)) != slot_index:
		return false
	cancel_targeting("cancelled")
	return true


func _confirm_current_preview() -> void:
	var handler: TargetAbilityBase = _session.get("handler", null) as TargetAbilityBase
	if handler == null:
		cancel_targeting("missing_handler")
		return
	var result: Dictionary = handler.confirm_target(_preview.duplicate(true), _get_session_context())
	if not bool(result.get("success", false)):
		return
	var payload: Dictionary = result.duplicate(true)
	payload["preview"] = _preview.duplicate(true)
	payload["session"] = get_session()
	targeting_confirmed.emit(payload)
	_clear_session()


func _prepare_caster_for_targeting() -> void:
	var caster: Node = _get_session_context().get("caster", null) as Node
	if caster == null or not is_instance_valid(caster):
		return
	if caster.has_method("cancel_movement"):
		caster.call("cancel_movement", true)
	if caster.has_method("clear_navigation_intent"):
		caster.call("clear_navigation_intent")
	if caster.has_method("clear_world_input_feedback"):
		caster.call("clear_world_input_feedback")


func _notify_targeting_cancelled(session: Dictionary, reason: String) -> void:
	if str(session.get("ability_kind", "")) != "skill":
		return
	if SkillModule != null and SkillModule.has_method("cancel_targeted_skill"):
		SkillModule.cancel_targeted_skill(str(session.get("ability_id", "")), reason)


func _clear_session() -> void:
	set_process(false)
	_session.clear()
	_preview.clear()
	if _overlay != null:
		_overlay.clear()


func _refresh_preview_from_pointer(force: bool = false) -> void:
	if not is_targeting():
		return
	var scene_root: Node = _resolve_scene_root()
	if scene_root == null:
		if force and _overlay != null:
			_overlay.clear()
		return
	var viewport: Viewport = scene_root.get_viewport()
	if viewport == null:
		return
	var pointer_pos: Vector2 = viewport.get_mouse_position()
	var ground_cell: Variant = _resolve_ground_cell(pointer_pos)
	if ground_cell is Vector3i:
		_update_preview_for_cell(ground_cell)
		return
	if force and _overlay != null:
		_overlay.clear()


func _refresh_preview_from_preferred_cell() -> void:
	var context: Dictionary = _get_session_context()
	var preferred: Variant = context.get("preferred_cell", null)
	if preferred is Vector3i:
		_update_preview_for_cell(preferred)


func _update_preview_for_cell(center_cell: Vector3i) -> void:
	var handler: TargetAbilityBase = _session.get("handler", null) as TargetAbilityBase
	var caster: Node = _get_session_context().get("caster", null) as Node
	if handler == null or caster == null:
		return
	_preview = handler.build_preview(caster, center_cell, _get_session_context())
	_update_overlay()
	preview_updated.emit(get_current_preview())


func _update_overlay() -> void:
	_ensure_overlay_attached()
	if _overlay == null:
		return
	var scene_root: Node = _resolve_scene_root()
	if scene_root == null:
		_overlay.clear()
		return
	var viewport: Viewport = scene_root.get_viewport()
	if viewport == null:
		_overlay.clear()
		return
	var camera: Camera3D = viewport.get_camera_3d()
	if camera == null:
		_overlay.clear()
		return

	_overlay.show_preview(
		_extract_cells(_preview.get("affected_cells", [])),
		_extract_cells(_preview.get("range_cells", [])),
		camera,
		bool(_preview.get("valid", false))
	)


func _ensure_overlay_attached() -> void:
	if _overlay == null:
		_overlay = GridAreaOverlay.new()
		_overlay.name = "GridAreaOverlay"
	var scene_root: Node = _resolve_scene_root()
	if scene_root == null:
		return
	if _overlay.get_parent() == scene_root:
		return
	var current_parent: Node = _overlay.get_parent()
	if current_parent != null:
		current_parent.remove_child(_overlay)
	scene_root.add_child(_overlay)


func _resolve_scene_root() -> Node:
	var context: Dictionary = _get_session_context()
	var provided_root: Node = context.get("scene_root", null) as Node
	if provided_root != null and is_instance_valid(provided_root):
		return provided_root
	var caster: Node = context.get("caster", null) as Node
	if caster != null and is_instance_valid(caster):
		if caster.has_method("get_targeting_scene_root"):
			var result: Variant = caster.call("get_targeting_scene_root")
			if result is Node and is_instance_valid(result):
				return result as Node
		var tree_from_caster: SceneTree = caster.get_tree()
		if tree_from_caster != null:
			return tree_from_caster.current_scene
	var tree: SceneTree = get_tree()
	if tree == null:
		return null
	return tree.current_scene


func _resolve_ground_cell(screen_pos: Vector2) -> Variant:
	var scene_root: Node = _resolve_scene_root()
	if scene_root == null:
		return null
	var caster: Node = _get_session_context().get("caster", null) as Node
	if caster == null or not is_instance_valid(caster):
		return null
	if not caster.has_method("get_interaction_system"):
		return null
	var interaction_system: Node = caster.call("get_interaction_system") as Node
	if interaction_system == null or not interaction_system.has_method("raycast_screen_position"):
		return null
	var ground_hit: Variant = interaction_system.call("raycast_screen_position", scene_root, screen_pos, true, 1)
	if not (ground_hit is Dictionary):
		return null
	var hit: Dictionary = ground_hit as Dictionary
	if hit.is_empty() or not hit.has("position"):
		return null
	return GridMovementSystem.world_to_grid(hit.position)


func _is_pointer_over_blocking_ui() -> bool:
	var scene_root: Node = _resolve_scene_root()
	if scene_root == null:
		return false
	var viewport: Viewport = scene_root.get_viewport()
	if viewport == null:
		return false
	var caster: Node = _get_session_context().get("caster", null) as Node
	if caster != null and is_instance_valid(caster) and caster.has_method("is_pointer_over_blocking_ui"):
		return bool(caster.call("is_pointer_over_blocking_ui", viewport))

	var hovered: Control = viewport.gui_get_hovered_control()
	if hovered == null or not is_instance_valid(hovered):
		return false
	if owns_control(hovered):
		return false
	var control: Control = hovered
	while control != null:
		if control.visible and control.mouse_filter == Control.MOUSE_FILTER_STOP:
			return true
		control = control.get_parent() as Control
	return false


func _get_session_context() -> Dictionary:
	var context: Variant = _session.get("context", {})
	if context is Dictionary:
		return context as Dictionary
	return {}


func _extract_cells(raw_cells: Variant) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	if not (raw_cells is Array):
		return result
	for cell_variant in raw_cells:
		if cell_variant is Vector3i:
			result.append(cell_variant)
	return result
