extends Node
class_name FunctionalTest_TargetAbilityBase

const TargetAbilityBase = preload("res://systems/target_ability_base.gd")


class PreviewAbility extends TargetAbilityBase:
	func configure_preview(config: Dictionary) -> void:
		ability_id = "preview_ability"
		ability_kind = "skill"
		_configure_targeting(config)


class DummyCaster extends Node3D:
	func get_grid_position() -> Vector3i:
		return GridMovementSystem.world_to_grid(global_position)


static func run_tests(runner: TestRunner) -> void:
	runner.register_test(
		"target_ability_base_builds_single_diamond_and_square_previews",
		TestRunner.TestLayer.FUNCTIONAL,
		TestRunner.TestPriority.P1_MAJOR,
		_test_preview_shapes
	)
	runner.register_test(
		"target_ability_base_marks_centers_outside_range_invalid",
		TestRunner.TestLayer.FUNCTIONAL,
		TestRunner.TestPriority.P1_MAJOR,
		_test_preview_range_validation
	)


static func _test_preview_shapes() -> void:
	var caster := DummyCaster.new()
	caster.position = Vector3(0.5, 0.0, 0.5)

	var single := PreviewAbility.new()
	single.configure_preview({"range_cells": 2, "shape": "single", "radius": 0})
	var single_preview: Dictionary = single.build_preview(caster, Vector3i(1, 0, 0), {"caster": caster})
	assert(single_preview.has("valid"), "Preview should expose valid flag")
	assert(single_preview.has("center_cell"), "Preview should expose center cell")
	assert(single_preview.has("affected_cells"), "Preview should expose affected cells")
	assert(single_preview.has("reason"), "Preview should expose reason")
	assert(single_preview.has("shape"), "Preview should expose shape")
	assert(single_preview.has("range_cells"), "Preview should expose range helper cells")
	assert((single_preview.get("affected_cells", []) as Array).size() == 1, "Single preview should only affect one cell")

	var diamond := PreviewAbility.new()
	diamond.configure_preview({"range_cells": 3, "shape": "diamond", "radius": 1})
	var diamond_preview: Dictionary = diamond.build_preview(caster, Vector3i(1, 0, 0), {"caster": caster})
	assert((diamond_preview.get("affected_cells", []) as Array).size() == 5, "Radius-1 diamond should affect 5 cells")

	var square := PreviewAbility.new()
	square.configure_preview({"range_cells": 3, "shape": "square", "radius": 1})
	var square_preview: Dictionary = square.build_preview(caster, Vector3i(1, 0, 0), {"caster": caster})
	assert((square_preview.get("affected_cells", []) as Array).size() == 9, "Radius-1 square should affect 9 cells")


static func _test_preview_range_validation() -> void:
	var caster := DummyCaster.new()
	caster.position = Vector3(0.5, 0.0, 0.5)

	var ability := PreviewAbility.new()
	ability.configure_preview({"range_cells": 1, "shape": "single", "radius": 0})
	var preview: Dictionary = ability.build_preview(caster, Vector3i(3, 0, 0), {"caster": caster})
	assert(not bool(preview.get("valid", false)), "Centers beyond range_cells should be invalid")
	assert(str(preview.get("reason", "")) == "out_of_range", "Out-of-range preview should expose a reason")
