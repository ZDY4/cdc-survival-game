extends RefCounted

const UIThemeService = preload("res://scripts/ui/ui_theme_service.gd")


func label3d(name: String, text: String, font_size: int, color: Color, outline_color: Color = Color(0.0, 0.0, 0.0, 0.78)) -> Label3D:
	var label := Label3D.new()
	label.name = name
	label.text = text
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = font_size
	label.modulate = color
	label.outline_size = 4
	label.outline_modulate = outline_color
	var font_result := UIThemeService.apply_label3d_font(label)
	label.set_meta("font_resource_path", str(font_result.get("font_resource_path", "")))
	return label


func cylinder_marker(
	name: String,
	top_radius: float,
	bottom_radius: float,
	height: float,
	radial_segments: int,
	material: Material
) -> MeshInstance3D:
	var marker := MeshInstance3D.new()
	marker.name = name
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_radius
	mesh.bottom_radius = bottom_radius
	mesh.height = height
	mesh.radial_segments = radial_segments
	marker.mesh = mesh
	marker.material_override = material
	return marker


func sphere_marker(name: String, radius: float, height: float, radial_segments: int, rings: int, material: Material) -> MeshInstance3D:
	var marker := MeshInstance3D.new()
	marker.name = name
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = radial_segments
	mesh.rings = rings
	marker.mesh = mesh
	marker.material_override = material
	return marker
