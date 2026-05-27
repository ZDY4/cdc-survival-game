extends RefCounted

var x: int
var y: int
var z: int


func _init(p_x: int = 0, p_y: int = 0, p_z: int = 0) -> void:
	x = p_x
	y = p_y
	z = p_z


static func from_dictionary(data: Dictionary) -> RefCounted:
	return load("res://scripts/core/grid/grid_coord.gd").new(
		int(data.get("x", 0)),
		int(data.get("y", 0)),
		int(data.get("z", 0))
	)


func to_dictionary() -> Dictionary:
	return {
		"x": x,
		"y": y,
		"z": z,
	}


func key() -> String:
	return "%d:%d:%d" % [x, y, z]
