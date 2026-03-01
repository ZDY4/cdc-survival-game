class_name GridVisualizer
extends Node3D

@export var grid_size := 1.0
@export var grid_range := 20
@export var line_color := Color(0.5, 0.5, 0.5, 0.3)
@export var line_width := 0.02

var _grid_mesh: MeshInstance3D = null

func _ready() -> void:
    visible = false
    _create_grid_mesh()

func show_grid() -> void:
    visible = true

func hide_grid() -> void:
    visible = false

func toggle_grid() -> void:
    visible = not visible

func _create_grid_mesh() -> void:
    _grid_mesh = MeshInstance3D.new()
    add_child(_grid_mesh)
    
    var immediate_mesh := ImmediateMesh.new()
    _grid_mesh.mesh = immediate_mesh
    _grid_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    
    var material := StandardMaterial3D.new()
    material.albedo_color = line_color
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    _grid_mesh.material_override = material
    
    immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
    
    var start := -grid_range * grid_size
    var end := grid_range * grid_size
    
    for i in range(-grid_range, grid_range + 1):
        var pos := i * grid_size
        
        # Horizontal lines
        immediate_mesh.surface_add_vertex(Vector3(start, 0.01, pos))
        immediate_mesh.surface_add_vertex(Vector3(end, 0.01, pos))
        
        # Vertical lines
        immediate_mesh.surface_add_vertex(Vector3(pos, 0.01, start))
        immediate_mesh.surface_add_vertex(Vector3(pos, 0.01, end))
    
    immediate_mesh.surface_end()
