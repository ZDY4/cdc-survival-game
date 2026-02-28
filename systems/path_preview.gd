class_name PathPreview
extends Node3D

@export var line_color := Color(0.2, 0.8, 1.0, 0.8)
@export var line_width := 0.1
@export var point_size := 0.2
@export var point_color := Color(0.2, 0.8, 1.0, 0.5)

var _line_mesh: MeshInstance3D = null
var _points: Array[MeshInstance3D] = []

func _ready() -> void:
    _line_mesh = MeshInstance3D.new()
    add_child(_line_mesh)

func show_path(path: Array[Vector3]) -> void:
    if path.is_empty():
        hide_path()
        return
    
    _clear_points()
    _draw_line(path)
    _draw_points(path)
    visible = true

func hide_path() -> void:
    visible = false
    _clear_points()
    if _line_mesh:
        _line_mesh.mesh = null

func _draw_line(path: Array[Vector3]) -> void:
    if path.size() < 2:
        return
    
    var immediate_mesh := ImmediateMesh.new()
    _line_mesh.mesh = immediate_mesh
    _line_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    
    var material := StandardMaterial3D.new()
    material.albedo_color = line_color
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    _line_mesh.material_override = material
    
    immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
    
    for pos in path:
        immediate_mesh.surface_add_vertex(pos + Vector3.UP * 0.1)
    
    immediate_mesh.surface_end()

func _draw_points(path: Array[Vector3]) -> void:
    for pos in path:
        var point := MeshInstance3D.new()
        point.mesh = SphereMesh.new()
        point.mesh.radius = point_size
        point.mesh.height = point_size * 2
        
        var material := StandardMaterial3D.new()
        material.albedo_color = point_color
        material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
        material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
        point.material_override = material
        
        point.position = pos + Vector3.UP * 0.1
        point.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        
        add_child(point)
        _points.append(point)

func _clear_points() -> void:
    for point in _points:
        point.queue_free()
    _points.clear()
