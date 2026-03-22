class_name PathPreview
extends Node3D

@export var line_color := Color(0.2, 0.8, 1.0, 0.8)
@export var line_width := 0.1
@export var point_size := 0.18
@export var point_color := Color(0.86, 0.86, 0.86, 0.5)

var _line_mesh: MeshInstance3D = null
var _points: Array[MeshInstance3D] = []
var _point_mesh: SphereMesh = null
var _line_material: StandardMaterial3D = null
var _point_material: StandardMaterial3D = null

func _ready() -> void:
    _line_mesh = MeshInstance3D.new()
    add_child(_line_mesh)
    _line_material = _build_line_material()
    _point_material = _build_point_material()
    _point_mesh = _build_point_mesh()
    _line_mesh.material_override = _line_material

func show_path(path: Array[Vector3]) -> void:
    if path.is_empty():
        hide_path()
        return
    
    _draw_line(path)
    _draw_points(path)
    visible = true

func hide_path() -> void:
    visible = false
    _hide_all_points()
    if _line_mesh:
        _line_mesh.mesh = null

func _draw_line(path: Array[Vector3]) -> void:
    if path.size() < 2:
        return
    
    var immediate_mesh := ImmediateMesh.new()
    _line_mesh.mesh = immediate_mesh
    _line_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    
    immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
    
    for pos in path:
        immediate_mesh.surface_add_vertex(pos + Vector3.UP * 0.1)
    
    immediate_mesh.surface_end()

func _draw_points(path: Array[Vector3]) -> void:
    var point_count: int = maxi(0, path.size() - 1)
    _ensure_point_capacity(point_count)
    for index in range(path.size()):
        if index == 0:
            continue
        var point_index: int = index - 1
        var pos: Vector3 = path[index]
        var point := _points[point_index]
        point.visible = true
        point.position = pos + Vector3.UP * 0.1
    for index in range(point_count, _points.size()):
        _points[index].visible = false

func _ensure_point_capacity(required_count: int) -> void:
    while _points.size() < required_count:
        var point := MeshInstance3D.new()
        point.mesh = _point_mesh
        point.material_override = _point_material
        point.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        point.visible = false
        add_child(point)
        _points.append(point)

func _hide_all_points() -> void:
    for point in _points:
        point.visible = false

func _build_line_material() -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = line_color
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    return material

func _build_point_material() -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = point_color
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    return material

func _build_point_mesh() -> SphereMesh:
    var mesh := SphereMesh.new()
    mesh.radius = point_size
    mesh.height = point_size * 2.0
    return mesh
