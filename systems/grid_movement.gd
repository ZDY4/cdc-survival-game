class_name GridMovement
extends Node

signal movement_started(path: Array[Vector3])
signal step_completed(world_pos: Vector3, step_index: int, total_steps: int)
signal movement_finished
signal movement_cancelled
signal movement_blocked(world_pos: Vector3, step_index: int, total_steps: int)

@export var step_duration := 0.25

var _current_path: Array[Vector3] = []
var _current_step := 0
var _is_moving := false
var _tween: Tween = null
var _cancel_requested_at_step_end := false
var _can_enter_step: Callable = Callable()

func move_along_path(path: Array[Vector3], target_node: Node3D, can_enter_step: Callable = Callable()) -> void:
    if path.is_empty():
        push_warning("Cannot move along empty path")
        return
    
    if _is_moving:
        cancel_movement()
    
    _current_path = path
    _current_step = 0
    _is_moving = true
    _cancel_requested_at_step_end = false
    _can_enter_step = can_enter_step
    
    movement_started.emit(path.duplicate())
    
    _execute_next_step(target_node)

func cancel_movement() -> void:
    if not _is_moving:
        return

    if _tween and _tween.is_valid():
        _cancel_requested_at_step_end = true
        return

    _stop_and_emit_cancelled()

func is_moving() -> bool:
    return _is_moving

func get_current_path() -> Array[Vector3]:
    return _current_path.duplicate()

func get_remaining_steps() -> int:
    return _current_path.size() - _current_step

func _execute_next_step(target_node: Node3D) -> void:
    if _current_step >= _current_path.size():
        _tween = null
        _is_moving = false
        _current_path.clear()
        _current_step = 0
        _cancel_requested_at_step_end = false
        _can_enter_step = Callable()
        movement_finished.emit()
        return
    
    var target_pos := _current_path[_current_step]
    if _can_enter_step.is_valid() and not bool(_can_enter_step.call(target_pos)):
        _stop_and_emit_blocked(target_pos)
        return
    
    # Kill old tween if exists
    if _tween and _tween.is_valid():
        _tween.kill()
    
    _tween = create_tween()
    _tween.set_trans(Tween.TRANS_QUAD)
    _tween.set_ease(Tween.EASE_IN_OUT)
    
    _tween.tween_property(target_node, "position", target_pos, step_duration)
    _tween.finished.connect(_on_step_completed.bind(target_node), CONNECT_ONE_SHOT)

func _on_step_completed(target_node: Node3D) -> void:
    _tween = null
    step_completed.emit(_current_path[_current_step], _current_step, _current_path.size())
    _current_step += 1
    if _cancel_requested_at_step_end:
        _stop_and_emit_cancelled()
        return
    _execute_next_step(target_node)

func _stop_and_emit_cancelled() -> void:
    if _tween and _tween.is_valid():
        _tween.kill()
    _tween = null
    _is_moving = false
    _current_path.clear()
    _current_step = 0
    _cancel_requested_at_step_end = false
    _can_enter_step = Callable()
    movement_cancelled.emit()

func _stop_and_emit_blocked(world_pos: Vector3) -> void:
    if _tween and _tween.is_valid():
        _tween.kill()
    _tween = null
    var blocked_step_index: int = _current_step
    var total_steps: int = _current_path.size()
    _is_moving = false
    _current_path.clear()
    _current_step = 0
    _cancel_requested_at_step_end = false
    _can_enter_step = Callable()
    movement_blocked.emit(world_pos, blocked_step_index, total_steps)
