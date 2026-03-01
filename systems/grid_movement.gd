class_name GridMovement
extends Node

signal movement_started(path: Array[Vector3])
signal step_completed(world_pos: Vector3, step_index: int, total_steps: int)
signal movement_finished
signal movement_cancelled

@export var step_duration := 0.4

var _current_path: Array[Vector3] = []
var _current_step := 0
var _is_moving := false
var _tween: Tween = null

func move_along_path(path: Array[Vector3], target_node: Node3D) -> void:
    if path.is_empty():
        push_warning("Cannot move along empty path")
        return
    
    if _is_moving:
        cancel_movement()
    
    _current_path = path
    _current_step = 0
    _is_moving = true
    
    movement_started.emit(path.duplicate())
    
    _execute_next_step(target_node)

func cancel_movement() -> void:
    if not _is_moving:
        return
    
    if _tween and _tween.is_valid():
        _tween.kill()
    
    _is_moving = false
    _current_path.clear()
    _current_step = 0
    
    movement_cancelled.emit()

func is_moving() -> bool:
    return _is_moving

func get_current_path() -> Array[Vector3]:
    return _current_path.duplicate()

func get_remaining_steps() -> int:
    return _current_path.size() - _current_step

func _execute_next_step(target_node: Node3D) -> void:
    if _current_step >= _current_path.size():
        _is_moving = false
        _current_path.clear()
        _current_step = 0
        movement_finished.emit()
        return
    
    var target_pos := _current_path[_current_step]
    
    _tween = create_tween()
    _tween.set_trans(Tween.TRANS_QUAD)
    _tween.set_ease(Tween.EASE_IN_OUT)
    
    _tween.tween_property(target_node, "position", target_pos, step_duration)
    _tween.finished.connect(_on_step_completed.bind(target_node))

func _on_step_completed(target_node: Node3D) -> void:
    step_completed.emit(_current_path[_current_step], _current_step, _current_path.size())
    _current_step += 1
    _execute_next_step(target_node)
