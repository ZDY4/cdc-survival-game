extends Node
class_name FunctionalTest_ProceduralBuilder

const WALL_SCRIPT_PATH: String = "res://addons/cdc_procedural_builder/runtime/proc_wall_3d.gd"
const FENCE_SCRIPT_PATH: String = "res://addons/cdc_procedural_builder/runtime/proc_fence_3d.gd"
const HOUSE_SCRIPT_PATH: String = "res://addons/cdc_procedural_builder/runtime/proc_house_3d.gd"
const OPENING_SCRIPT_PATH: String = "res://addons/cdc_procedural_builder/runtime/house_opening_resource.gd"
const GAME_WORLD_SCENE_PATH: String = "res://scenes/locations/game_world_3d.tscn"

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

	runner.register_test(
		"procedural_house_gable_roof_adds_ridge_height",
		TestRunner.TestLayer.FUNCTIONAL,
		TestRunner.TestPriority.P1_MAJOR,
		_test_house_gable_roof_adds_ridge_height
	)

	runner.register_test(
		"procedural_fence_post_height_uses_post_size",
		TestRunner.TestLayer.FUNCTIONAL,
		TestRunner.TestPriority.P1_MAJOR,
		_test_fence_post_height_uses_post_size
	)

	runner.register_test(
		"procedural_concave_polygon_interior_point_stays_inside",
		TestRunner.TestLayer.FUNCTIONAL,
		TestRunner.TestPriority.P1_MAJOR,
		_test_concave_polygon_interior_point_stays_inside
	)

	runner.register_test(
		"procedural_scene_instances_generate_expected_meshes",
		TestRunner.TestLayer.FUNCTIONAL,
		TestRunner.TestPriority.P1_MAJOR,
		_test_scene_instances_generate_expected_meshes
	)

	runner.register_test(
		"procedural_two_point_paths_force_open_state",
		TestRunner.TestLayer.FUNCTIONAL,
		TestRunner.TestPriority.P1_MAJOR,
		_test_two_point_paths_force_open_state
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

static func _test_house_gable_roof_adds_ridge_height() -> void:
	var house: ProcHouse3D = _new_script_instance(HOUSE_SCRIPT_PATH)
	house.wall_height = 3.0
	house.roof_height = 1.5
	house.roof_mode = ProcHouse3D.RoofMode.GABLE
	house.set_control_points([
		Vector3(-3.0, 0.0, -2.0),
		Vector3(3.0, 0.0, -2.0),
		Vector3(3.0, 0.0, 2.0),
		Vector3(-3.0, 0.0, 2.0)
	])
	house.rebuild_geometry()

	var mesh: Mesh = house.get_preview_mesh_instance().mesh
	assert(mesh != null, "Gable house should generate a mesh")
	assert(_mesh_max_y(mesh) > house.wall_height + house.roof_height * 0.9, "Gable roof should raise the ridge above the wall top")

static func _test_fence_post_height_uses_post_size() -> void:
	var fence: ProcFence3D = _new_script_instance(FENCE_SCRIPT_PATH)
	fence.fence_height = 2.0
	fence.post_size = Vector3(0.2, 4.0, 0.2)
	fence.rail_count = 1
	fence.rail_thickness = 0.2
	fence.set_control_points([
		Vector3.ZERO,
		Vector3(4.0, 0.0, 0.0)
	])
	fence.rebuild_geometry()

	var mesh: Mesh = fence.get_preview_mesh_instance().mesh
	assert(mesh != null, "Fence should generate a mesh when validating post height")
	assert(_mesh_max_y(mesh) > 3.9, "Fence post mesh should use post_size.y instead of fence_height")

static func _test_concave_polygon_interior_point_stays_inside() -> void:
	var points: Array[Vector3] = [
		Vector3(-3.0, 0.0, -3.0),
		Vector3(3.0, 0.0, -3.0),
		Vector3(3.0, 0.0, -1.0),
		Vector3(-1.0, 0.0, -1.0),
		Vector3(-1.0, 0.0, 1.0),
		Vector3(3.0, 0.0, 1.0),
		Vector3(3.0, 0.0, 3.0),
		Vector3(-3.0, 0.0, 3.0)
	]
	var average_point: Vector3 = Vector3.ZERO
	for point in points:
		average_point += point
	average_point /= float(points.size())

	var polygon: PackedVector2Array = PackedVector2Array()
	for point in points:
		polygon.append(Vector2(point.x, point.z))

	assert(not Geometry2D.is_point_in_polygon(Vector2(average_point.x, average_point.z), polygon), "Concave regression polygon should place the arithmetic mean outside the footprint")

	var interior_point: Vector3 = ProcGeometryUtils.find_polygon_interior_point_xz(points, 1.0)
	assert(Geometry2D.is_point_in_polygon(Vector2(interior_point.x, interior_point.z), polygon), "Interior point helper should stay inside a concave footprint")
	assert(is_equal_approx(interior_point.y, 1.0), "Interior point helper should preserve the requested Y coordinate")

static func _test_scene_instances_generate_expected_meshes() -> void:
	var scene_resource: PackedScene = load(GAME_WORLD_SCENE_PATH)
	assert(scene_resource != null, "Game world scene should load")

	var scene_instance: Node = scene_resource.instantiate()
	assert(scene_instance != null, "Game world scene should instantiate")

	var wall: ProcWall3D = scene_instance.get_node_or_null("ProcWall3D")
	var fence: ProcFence3D = scene_instance.get_node_or_null("ProcFence3D")
	var house: ProcHouse3D = scene_instance.get_node_or_null("ProcHouse3D")
	assert(wall != null, "Game world scene should include ProcWall3D")
	assert(fence != null, "Game world scene should include ProcFence3D")
	assert(house != null, "Game world scene should include ProcHouse3D")

	wall.rebuild_geometry()
	fence.rebuild_geometry()
	house.rebuild_geometry()

	assert(wall.get_preview_mesh_instance().mesh != null, "Scene wall should generate a preview mesh")
	assert(fence.get_preview_mesh_instance().mesh != null, "Scene fence should generate a preview mesh")
	assert(house.get_preview_mesh_instance().mesh != null, "Scene house should generate a preview mesh")
	assert(wall.get_segment_count() == 4, "Scene wall should remain a closed four-segment loop")
	assert(not fence.closed, "Scene fence should use an open path for its two-point layout")
	assert(fence.get_segment_count() == 1, "Scene fence should generate a single visible segment")
	assert(house.get_collision_root().get_child_count() == 1, "Scene house should still build a trimesh collision shape")

	scene_instance.queue_free()

static func _test_two_point_paths_force_open_state() -> void:
	var wall: ProcWall3D = _new_script_instance(WALL_SCRIPT_PATH)
	wall.set_control_points([
		Vector3.ZERO,
		Vector3(4.0, 0.0, 0.0)
	])
	assert(not wall.can_edit_closed_state(), "Two-point wall should not allow closed editing")
	wall.set_closed(true)
	assert(not wall.closed, "Two-point wall should force closed back to false")
	assert(wall.get_segment_count() == 1, "Two-point wall should only expose one visible segment")

	var wall_closed_property: Dictionary = {"name": "closed", "usage": PROPERTY_USAGE_DEFAULT}
	wall._validate_property(wall_closed_property)
	assert((int(wall_closed_property["usage"]) & PROPERTY_USAGE_READ_ONLY) != 0, "Two-point wall should expose closed as read-only in the inspector")

	wall.append_control_point(Vector3(4.0, 0.0, 4.0))
	assert(wall.can_edit_closed_state(), "Wall should allow closed editing once it has three points")
	wall.set_closed(true)
	assert(wall.closed, "Wall should allow closed once it has three points")

	var fence: ProcFence3D = _new_script_instance(FENCE_SCRIPT_PATH)
	fence.set_control_points([
		Vector3.ZERO,
		Vector3(5.0, 0.0, -1.0)
	])
	assert(not fence.can_edit_closed_state(), "Two-point fence should not allow closed editing")
	fence.set_closed(true)
	assert(not fence.closed, "Two-point fence should force closed back to false")

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

static func _mesh_max_y(mesh: Mesh) -> float:
	var max_y: float = -INF
	for surface_index in range(mesh.get_surface_count()):
		var surface_arrays: Array = mesh.surface_get_arrays(surface_index)
		var vertices: PackedVector3Array = surface_arrays[Mesh.ARRAY_VERTEX]
		for vertex in vertices:
			max_y = maxf(max_y, vertex.y)
	return max_y

static func _blocked_cells_contains(cells: Array[Vector3i], target: Vector3i) -> bool:
	for cell in cells:
		if cell == target:
			return true
	return false
