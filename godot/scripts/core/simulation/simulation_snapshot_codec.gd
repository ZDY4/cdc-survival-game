extends RefCounted

const SimulationSnapshotLoader = preload("res://scripts/core/simulation/simulation_snapshot_loader.gd")

var _loader := SimulationSnapshotLoader.new()


func load(simulation: RefCounted, snapshot_data: Dictionary) -> void:
	_loader.load(simulation, snapshot_data)