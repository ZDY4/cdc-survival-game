@tool
class_name HouseOpeningResource
extends Resource

@export_enum("door", "window") var opening_type: String = "door"
@export var edge_index: int = 0
@export var offset_on_edge: float = 1.0
@export var width: float = 1.2
@export var height: float = 2.0
@export var sill_height: float = 0.0

func duplicate_opening() -> HouseOpeningResource:
	var duplicated: HouseOpeningResource = HouseOpeningResource.new()
	duplicated.opening_type = opening_type
	duplicated.edge_index = edge_index
	duplicated.offset_on_edge = offset_on_edge
	duplicated.width = width
	duplicated.height = height
	duplicated.sill_height = sill_height
	return duplicated

func get_label() -> String:
	return "%s edge=%d offset=%.2f" % [opening_type, edge_index, offset_on_edge]
