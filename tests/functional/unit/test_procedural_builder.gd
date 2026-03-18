extends Node
class_name FunctionalTest_ProceduralBuilder

const WALL_SCRIPT_PATH: String = "res://addons/cdc_procedural_builder/runtime/proc_wall_3d.gd"
const FENCE_SCRIPT_PATH: String = "res://addons/cdc_procedural_builder/runtime/proc_fence_3d.gd"
const HOUSE_SCRIPT_PATH: String = "res://addons/cdc_procedural_builder/runtime/proc_house_3d.gd"
const OPENING_SCRIPT_PATH: String = "res://addons/cdc_procedural_builder/runtime/house_opening_resource.gd"

static func run_tests(runner: TestRunner) -> void:
	runner.register_test(
		"procedural_wall_rebuild_updates_mesh_bounds",
		TestRunner.TestLayer.FUNCTIONAL,
		TestRunner.TestPriority.P1_MAJOR,
		_test_wall_rebuild_updates_mesh_bounds
	)

	runner.register_test(
		"procedural_fence_post_count_changes_with_spacing",
		TestRunner.TestLayer.FUNCTIONAL,
		TestRunner.TestPriority.P1_MAJOR,
		_test_fence_post_count_changes_with_spacing
	)

	runner.register_test(
		"procedural_house_generates_mesh_and_collision",
		TestRunner.TestLayer.FUNCTIONAL,
		TestRunner.TestPriority.P1_MAJOR,
		_test_house_generates_mesh_and_collision
	)

	runner.register_test(
		"procedural_house_opening_applies_and_clamps",
		TestRunner.TestLayer.FUNCTIONAL,
		TestRunner.TestPriority.P1_MAJOR,
		_test_house_opening_applies_and_clamps
	)

	runner.register_test(
		"procedural_open_closed_collision_counts",
		TestRunner.TestLayer.FUNCTIONAL,
		TestRunner.TestPriority.P1_MAJOR,
		_test_open_closed_collision_counts
	)

	runner.register_test(
		"procedural_wall_corner_uses_miter_joint",
		TestRunner.TestLayer.FUNCTIONAL,
		TestRunner.TestPriority.P1_MAJOR,
		_test_wall_corner_uses_miter_joint
	)

	runner.register_test(
		"procedural_fence_rail_corner_uses_miter_joint",
		TestRunner.TestLayer.FUNCTIONAL,
		TestRunner.TestPriority.P1_MAJOR,
		_test_fence_rail_corner_uses_miter_joint
	)

	runner.register_test(
		"procedural_wall_generates_blocked_grid_cells",
		TestRunner.TestLayer.FUNCTIONAL,
		TestRunner.TestPriority.P1_MAJOR,
		_test_wall_generates_blocked_grid_cells
	)

	runner.register_test(
		"procedural_fence_generates_blocked_grid_cells",
		TestRunner.TestLayer.FUNCTIONAL,
		TestRunner.TestPriority.P1_MAJOR,
		_test_fence_generates_blocked_grid_cells
	)

	runner.register_test(
		"procedural_snap_step_applies_to_points",
		TestRunner.TestLayer.FUNCTIONAL,
		TestRunner.TestPriority.P1_MAJOR,
		_test_snap_step_applies_to_points
	)

static func _test_wall_rebuild_updates_mesh_bounds() -> void:
	var wall: ProcWall3D = _new_script_instance(WALL_SCRIPT_PATH)
	wall.set_control_points([Vector3.ZERO, Vector3(4.0, 0.0, 0.0)])
	wall.rebuild_geometry()
	var initial_mesh: Mesh = wall.get_preview_mesh_instance().mesh
	assert(initial_mesh != null, "Wall mesh should be generated")
	var initial_bounds: AABB = initial_mesh.get_aabb()

	wall.set_control_points([Vector3.ZERO, Vector3(8.0, 0.0, 0.0)])
	wall.rebuild_geometry()
	var updated_mesh: Mesh = wall.get_preview_mesh_instance().mesh
	var updated_bounds: AABB = updated_mesh.get_aabb()

	assert(updated_bounds.size.length() > initial_bounds.size.length(), "Wall bounds should grow after extending control points")

static func _test_fence_post_count_changes_with_spacing() -> void:
	var fence: ProcFence3D = _new_script_instance(FENCE_SCRIPT_PATH)
	fence.set_control_points([Vector3.ZERO, Vector3(6.0, 0.0, 0.0)])
	fence.post_spacing = 3.0
	fence.rebuild_geometry()
	var sparse_info: Dictionary = fence.get_last_build_info()

	fence.post_spacing = 1.5
	fence.rebuild_geometry()
	var dense_info: Dictionary = fence.get_last_build_info()

	assert(int(dense_info.get("post_count", 0)) > int(sparse_info.get("post_count", 0)), "Fence should create more posts with smaller spacing")

static func _test_house_generates_mesh_and_collision() -> void:
	var house: ProcHouse3D = _new_script_instance(HOUSE_SCRIPT_PATH)
	house.set_control_points([
		Vector3(-3.0, 0.0, -2.0),
		Vector3(3.0, 0.0, -2.0),
		Vector3(3.0, 0.0, 2.0),
		Vector3(-3.0, 0.0, 2.0)
	])
	house.rebuild_geometry()

	var mesh: Mesh = house.get_preview_mesh_instance().mesh
	assert(mesh != null, "House mesh should be generated")
	assert(mesh.get_surface_count() > 0, "House mesh should contain surfaces")
	assert(house.get_collision_root().get_child_count() == 1, "House should create a single trimesh collision shape")

static func _test_house_opening_applies_and_clamps() -> void:
	var house: ProcHouse3D = _new_script_instance(HOUSE_SCRIPT_PATH)
	house.set_control_points([
		Vector3(-2.0, 0.0, -2.0),
		Vector3(2.0, 0.0, -2.0),
		Vector3(2.0, 0.0, 2.0),
		Vector3(-2.0, 0.0, 2.0)
	])
	house.rebuild_geometry()
	var base_info: Dictionary = house.get_last_build_info()

	var opening: HouseOpeningResource = _new_script_instance(OPENING_SCRIPT_PATH)
	opening.edge_index = 0
	opening.offset_on_edge = 0.1
	opening.width = 10.0
	opening.height = 10.0
	opening.sill_height = 0.0
	house.set_openings([opening])
	house.rebuild_geometry()
	var opening_info: Dictionary = house.get_last_build_info()

	assert(int(opening_info.get("applied_opening_count", 0)) == 1, "House opening should be applied after clamping to edge bounds")
	assert(int(opening_info.get("wall_piece_count", 0)) > int(base_info.get("wall_piece_count", 0)), "Opening should split wall geometry into more pieces")

static func _test_open_closed_collision_counts() -> void:
	var wall: ProcWall3D = _new_script_instance(WALL_SCRIPT_PATH)
	wall.set_control_points([
		Vector3.ZERO,
		Vector3(4.0, 0.0, 0.0),
		Vector3(4.0, 0.0, 4.0)
	])
	wall.set_closed(false)
	wall.rebuild_geometry()
	var open_collision_count: int = wall.get_collision_root().get_child_count()

	wall.set_closed(true)
	wall.rebuild_geometry()
	var closed_collision_count: int = wall.get_collision_root().get_child_count()

	assert(open_collision_count == 2, "Open wall path should create one collision box per visible segment")
	assert(closed_collision_count == 3, "Closed wall path should add the final closing segment")

static func _test_wall_corner_uses_miter_joint() -> void:
	var wall: ProcWall3D = _new_script_instance(WALL_SCRIPT_PATH)
	wall.wall_thickness = 1.0
	wall.wall_height = 2.0
	wall.cap_ends = false
	wall.set_closed(false)
	wall.set_control_points([
		Vector3.ZERO,
		Vector3(4.0, 0.0, 0.0),
		Vector3(4.0, 0.0, 4.0)
	])
	wall.rebuild_geometry()

	var mesh: Mesh = wall.get_preview_mesh_instance().mesh
	assert(mesh != null, "Wall corner test should generate a mesh")
	assert(
		_mesh_contains_vertex_near(mesh, Vector3(3.5, 0.0, 0.5)),
		"Wall mesh should include the inner miter corner vertex"
	)
	assert(
		_mesh_contains_vertex_near(mesh, Vector3(4.5, 0.0, -0.5)),
		"Wall mesh should include the outer miter corner vertex"
	)
	assert(
		not _mesh_contains_vertex_near(mesh, Vector3(4.5, 0.0, 0.5)),
		"Wall mesh should no longer keep the old box-overlap corner vertex"
	)

static func _test_fence_rail_corner_uses_miter_joint() -> void:
	var fence: ProcFence3D = _new_script_instance(FENCE_SCRIPT_PATH)
	fence.fence_height = 2.0
	fence.rail_count = 1
	fence.rail_thickness = 0.4
	fence.post_size = Vector3(0.1, 2.0, 0.1)
	fence.set_closed(false)
	fence.set_control_points([
		Vector3.ZERO,
		Vector3(4.0, 0.0, 0.0),
		Vector3(4.0, 0.0, 4.0)
	])
	fence.rebuild_geometry()

	var mesh: Mesh = fence.get_preview_mesh_instance().mesh
	assert(mesh != null, "Fence corner test should generate a mesh")
	assert(
		_mesh_contains_vertex_near(mesh, Vector3(3.8, 0.8, 0.2)),
		"Fence rail mesh should include the inner miter corner vertex"
	)
	assert(
		_mesh_contains_vertex_near(mesh, Vector3(4.2, 0.8, -0.2)),
		"Fence rail mesh should include the outer miter corner vertex"
	)
	assert(
		not _mesh_contains_vertex_near(mesh, Vector3(4.2, 0.8, 0.2)),
		"Fence rail mesh should no longer keep the old box-overlap corner vertex"
	)

static func _test_wall_generates_blocked_grid_cells() -> void:
	var wall: ProcWall3D = _new_script_instance(WALL_SCRIPT_PATH)
	wall.wall_thickness = 1.0
	wall.cap_ends = false
	wall.block_grid_navigation = true
	wall.set_control_points([
		Vector3.ZERO,
		Vector3(4.0, 0.0, 0.0)
	])
	wall.rebuild_geometry()

	var blocked_cells: Array[Vector3i] = wall.get_blocked_grid_cells_copy()
	assert(not blocked_cells.is_empty(), "Wall should publish blocked grid cells when navigation blocking is enabled")
	assert(
		_blocked_cells_contains(blocked_cells, Vector3i(1, 0, -1)),
		"Wall should block cells overlapping its footprint on the negative Z side"
	)
	assert(
		_blocked_cells_contains(blocked_cells, Vector3i(1, 0, 0)),
		"Wall should block cells overlapping its footprint on the positive Z side"
	)

	wall.block_grid_navigation = false
	assert(wall.get_blocked_grid_cells_copy().is_empty(), "Disabling navigation blocking should clear blocked cells")

static func _test_fence_generates_blocked_grid_cells() -> void:
	var fence: ProcFence3D = _new_script_instance(FENCE_SCRIPT_PATH)
	fence.rail_count = 1
	fence.rail_thickness = 0.4
	fence.post_size = Vector3(0.4, 2.0, 0.4)
	fence.block_grid_navigation = true
	fence.set_control_points([
		Vector3.ZERO,
		Vector3(4.0, 0.0, 0.0)
	])
	fence.rebuild_geometry()

	var blocked_cells: Array[Vector3i] = fence.get_blocked_grid_cells_copy()
	assert(not blocked_cells.is_empty(), "Fence should publish blocked grid cells when navigation blocking is enabled")
	assert(
		_blocked_cells_contains(blocked_cells, Vector3i(0, 0, -1)) or _blocked_cells_contains(blocked_cells, Vector3i(0, 0, 0)),
		"Fence should block at least one cell around its first post"
	)

static func _test_snap_step_applies_to_points() -> void:
	var wall: ProcWall3D = _new_script_instance(WALL_SCRIPT_PATH)
	wall.snap_enabled = true
	wall.snap_step = 0.5
	wall.set_control_points([
		Vector3(0.33, 0.0, 0.74),
		Vector3(3.24, 0.0, 1.26)
	])

	assert(wall.get_control_point(0).is_equal_approx(Vector3(0.5, 0.0, 0.5)), "First point should snap to the configured grid")
	assert(wall.get_control_point(1).is_equal_approx(Vector3(3.0, 0.0, 1.5)), "Second point should snap to the configured grid")

static func _new_script_instance(path: String) -> Variant:
	var script: Script = load(path)
	assert(script != null, "Script should load: %s" % path)
	var instance: Variant = script.new()
	assert(instance != null, "Script instance should be created: %s" % path)
	return instance

static func _mesh_contains_vertex_near(mesh: Mesh, target: Vector3, tolerance: float = 0.05) -> bool:
	for surface_index in range(mesh.get_surface_count()):
		var surface_arrays: Array = mesh.surface_get_arrays(surface_index)
		var vertices: PackedVector3Array = surface_arrays[Mesh.ARRAY_VERTEX]
		for vertex in vertices:
			if vertex.distance_to(target) <= tolerance:
				return true
	return false

static func _blocked_cells_contains(cells: Array[Vector3i], target: Vector3i) -> bool:
	for cell in cells:
		if cell == target:
			return true
	return false
