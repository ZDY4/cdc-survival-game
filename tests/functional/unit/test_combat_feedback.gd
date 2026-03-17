extends Node
class_name FunctionalTest_CombatFeedback

const CharacterActor = preload("res://systems/character_actor.gd")
const CameraController3D = preload("res://systems/camera_controller_3d.gd")
const HitReaction3D = preload("res://systems/hit_reaction_3d.gd")
const WorldDamageTextController = preload("res://systems/world_damage_text_controller.gd")

class DummyReactionTarget:
	extends Node3D

	var visual_root: Node3D = null
	var explicit_target: Node3D = null

	func _ready() -> void:
		visual_root = Node3D.new()
		visual_root.name = "VisualRoot"
		add_child(visual_root)
		explicit_target = Node3D.new()
		explicit_target.name = "ExplicitTarget"
		add_child(explicit_target)

	func get_hit_reaction_target() -> Node3D:
		return explicit_target

static func run_tests(runner: TestRunner) -> void:
	runner.register_test(
		"world_damage_text_controller_spawns_and_cleans_up_labels",
		TestRunner.TestLayer.FUNCTIONAL,
		TestRunner.TestPriority.P1_MAJOR,
		_test_world_damage_text_cleanup
	)
	runner.register_test(
		"hit_reaction_uses_visual_root_and_resets_position",
		TestRunner.TestLayer.FUNCTIONAL,
		TestRunner.TestPriority.P1_MAJOR,
		_test_hit_reaction_visual_root_reset
	)
	runner.register_test(
		"hit_reaction_prefers_explicit_target_over_owner_root",
		TestRunner.TestLayer.FUNCTIONAL,
		TestRunner.TestPriority.P1_MAJOR,
		_test_hit_reaction_prefers_explicit_target
	)
	runner.register_test(
		"camera_controller_shake_returns_to_follow_position",
		TestRunner.TestLayer.FUNCTIONAL,
		TestRunner.TestPriority.P1_MAJOR,
		_test_camera_shake_resets
	)
	runner.register_test(
		"character_actor_attack_lunge_returns_visual_root_to_origin",
		TestRunner.TestLayer.FUNCTIONAL,
		TestRunner.TestPriority.P1_MAJOR,
		_test_character_attack_lunge_resets
	)

static func _test_world_damage_text_cleanup() -> void:
	var tree := _require_tree()
	var controller := WorldDamageTextController.new()
	var target := Node3D.new()
	tree.root.add_child(controller)
	tree.root.add_child(target)
	await tree.process_frame

	controller.show_damage_number(target, 12, false)
	assert(controller.get_child_count() == 1, "Damage text controller should spawn one floating label")

	await tree.create_timer(0.75).timeout
	assert(controller.get_child_count() == 0, "Floating damage labels should clean themselves up after the tween")

	target.queue_free()
	controller.queue_free()
	await tree.process_frame

static func _test_hit_reaction_visual_root_reset() -> void:
	var tree := _require_tree()
	var target := Node3D.new()
	var visual_root := Node3D.new()
	visual_root.name = "VisualRoot"
	target.add_child(visual_root)
	tree.root.add_child(target)
	await tree.process_frame

	var reaction := HitReaction3D.get_or_create(target)
	var original_visual_position := visual_root.position
	reaction.play_hit_shake()
	await tree.process_frame

	assert(target.position.is_equal_approx(Vector3.ZERO), "Hit reaction should not move the target root")
	assert(not visual_root.position.is_equal_approx(original_visual_position), "Hit reaction should shake the visual root")

	await tree.create_timer(0.25).timeout
	assert(visual_root.position.is_equal_approx(original_visual_position), "Visual root should return to its original position after shaking")

	target.queue_free()
	await tree.process_frame

static func _test_hit_reaction_prefers_explicit_target() -> void:
	var tree := _require_tree()
	var target := DummyReactionTarget.new()
	tree.root.add_child(target)
	await tree.process_frame

	var reaction := HitReaction3D.get_or_create(target)
	var explicit_original := target.explicit_target.position
	var visual_original := target.visual_root.position
	reaction.play_hit_shake()
	await tree.process_frame

	assert(not target.explicit_target.position.is_equal_approx(explicit_original), "Explicit hit reaction target should be shaken first")
	assert(target.visual_root.position.is_equal_approx(visual_original), "VisualRoot should stay still when an explicit reaction target exists")

	await tree.create_timer(0.25).timeout
	assert(target.explicit_target.position.is_equal_approx(explicit_original), "Explicit target should reset after hit shake")

	target.queue_free()
	await tree.process_frame

static func _test_camera_shake_resets() -> void:
	var tree := _require_tree()
	var target := Node3D.new()
	target.global_position = Vector3(2.0, 0.0, -1.0)
	var camera := CameraController3D.new()
	camera.target = target
	tree.root.add_child(target)
	tree.root.add_child(camera)
	await tree.process_frame
	await tree.process_frame

	var base_position := camera.global_position
	camera.play_shake(0.2, 0.1, 1.2)
	await tree.process_frame
	await tree.process_frame

	assert(camera.global_position.distance_to(base_position) > 0.001, "Camera shake should add a temporary positional offset")

	await tree.create_timer(0.35).timeout
	assert(camera.global_position.distance_to(base_position) < 0.01, "Camera position should settle back to its follow target after shake")

	camera.queue_free()
	target.queue_free()
	await tree.process_frame

static func _test_character_attack_lunge_resets() -> void:
	var tree := _require_tree()
	var actor := CharacterActor.new()
	tree.root.add_child(actor)
	await tree.process_frame

	var visual_root := actor.get_visual_root()
	assert(visual_root != null, "CharacterActor should always create a visual root for placeholder visuals")

	await actor.play_attack_lunge(Vector3(3.0, 0.0, 0.0))
	assert(visual_root.position.is_equal_approx(Vector3.ZERO), "Attack lunge should restore the visual root back to origin")

	actor.queue_free()
	await tree.process_frame

static func _require_tree() -> SceneTree:
	var loop := Engine.get_main_loop()
	assert(loop is SceneTree, "Main loop should be a SceneTree")
	var tree := loop as SceneTree
	assert(tree.root != null, "SceneTree root should exist")
	return tree
