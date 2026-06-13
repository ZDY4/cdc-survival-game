class_name WorldLightRig
extends Node3D


func sync_lights(_map_snapshot: Dictionary) -> Dictionary:
	if get_node_or_null("Sun") == null:
		var sun := DirectionalLight3D.new()
		sun.name = "Sun"
		sun.rotation_degrees = Vector3(-52.0, 36.0, 0.0)
		sun.light_energy = 1.4
		add_child(sun)
	return {"count": 1}
