extends Node
class_name FunctionalTest_InteractableHoverOutline

const Interactable = preload("res://modules/interaction/interactable.gd")
const InteractionOption = preload("res://modules/interaction/options/interaction_option.gd")
const PlayerController = preload("res://systems/player_controller.gd")

class DummyOutlineTarget:
	extends Node3D

	var last_visible: bool = false
	var last_color: Color = Color(0.0, 0.0, 0.0, 0.0)

	func set_hover_outline_visible(visible: bool) -> void:
		last_visible = visible

	func set_hover_outline_color(color: Color) -> void:
		last_color = color

class DummyInteractionOption:
	extends InteractionOption

	var dangerous: bool = false

	func is_dangerous(_interactable: Node) -> bool:
		return dangerous

static func run_tests(runner: TestRunner) -> void:
	runner.register_test(
		"interactable_hover_outline_target_defaults_to_parent",
		TestRunner.TestLayer.FUNCTIONAL,
		TestRunner.TestPriority.P1_MAJOR,
		_test_hover_outline_target_defaults_to_parent
	)
	runner.register_test(
		"interactable_hover_outline_target_uses_explicit_path",
		TestRunner.TestLayer.FUNCTIONAL,
		TestRunner.TestPriority.P1_MAJOR,
		_test_hover_outline_target_uses_explicit_path
	)
	runner.register_test(
		"player_controller_updates_generic_hover_outline_target",
		TestRunner.TestLayer.FUNCTIONAL,
		TestRunner.TestPriority.P1_MAJOR,
		_test_player_controller_updates_generic_hover_outline_target
	)

static func _test_hover_outline_target_defaults_to_parent() -> void:
	var tree := _require_tree()
	var root := Node3D.new()
	var interactable := Interactable.new()
	root.add_child(interactable)
	tree.root.add_child(root)
	await tree.process_frame

	assert(interactable.get_hover_outline_target() == root, "Interactable should default hover outline target to its parent node")

	root.queue_free()
	await tree.process_frame

static func _test_hover_outline_target_uses_explicit_path() -> void:
	var tree := _require_tree()
	var root := Node3D.new()
	var outline_target := DummyOutlineTarget.new()
	outline_target.name = "OutlineTarget"
	var interactable := Interactable.new()
	interactable.hover_outline_target_path = NodePath("../OutlineTarget")
	root.add_child(outline_target)
	root.add_child(interactable)
	tree.root.add_child(root)
	await tree.process_frame

	assert(interactable.get_hover_outline_target() == outline_target, "Interactable should resolve the configured hover outline target path")

	root.queue_free()
	await tree.process_frame

static func _test_player_controller_updates_generic_hover_outline_target() -> void:
	var tree := _require_tree()
	var player := PlayerController.new()
	tree.root.add_child(player)

	var target_root := Node3D.new()
	var outline_target := DummyOutlineTarget.new()
	outline_target.name = "OutlineTarget"
	var interactable := Interactable.new()
	interactable.hover_outline_target_path = NodePath("../OutlineTarget")
	target_root.add_child(outline_target)
	target_root.add_child(interactable)
	tree.root.add_child(target_root)
	await tree.process_frame

	var safe_option := DummyInteractionOption.new()
	player._update_hover_outline_target(interactable, safe_option)
	assert(outline_target.last_visible, "Hover outline target should be shown for non-character interactables")
	assert(outline_target.last_color == Color(1.0, 1.0, 1.0, 1.0), "Safe primary interactions should use a white outline")

	var dangerous_option := DummyInteractionOption.new()
	dangerous_option.dangerous = true
	player._update_hover_outline_target(interactable, dangerous_option)
	assert(outline_target.last_color == InteractionOption.DANGEROUS_DISPLAY_COLOR, "Dangerous primary interactions should use the dangerous outline color")

	player._clear_hover_outline_target()
	assert(not outline_target.last_visible, "Clearing hover feedback should hide the outline target")

	target_root.queue_free()
	player.queue_free()
	await tree.process_frame

static func _require_tree() -> SceneTree:
	var loop := Engine.get_main_loop()
	assert(loop is SceneTree, "Main loop should be a SceneTree")
	var tree := loop as SceneTree
	assert(tree.root != null, "SceneTree root should exist")
	return tree
