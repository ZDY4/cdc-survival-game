extends Node
class_name FunctionalTest_CraftingSystem


static func run_tests(runner: TestRunner) -> void:
	runner.register_test(
		"crafting_system_loads_directory_recipes",
		TestRunner.TestLayer.FUNCTIONAL,
		TestRunner.TestPriority.P0_CRITICAL,
		_test_loads_directory_recipes
	)

	runner.register_test(
		"crafting_system_unlocks_default_recipes",
		TestRunner.TestLayer.FUNCTIONAL,
		TestRunner.TestPriority.P0_CRITICAL,
		_test_unlocks_default_recipes
	)

	runner.register_test(
		"crafting_system_marks_repair_recipes",
		TestRunner.TestLayer.FUNCTIONAL,
		TestRunner.TestPriority.P1_MAJOR,
		_test_marks_repair_recipes
	)


static func _test_loads_directory_recipes() -> void:
	var crafting_system := _get_autoload("CraftingSystem")
	assert(crafting_system != null, "CraftingSystem autoload should exist")
	assert(crafting_system.has_method("has_recipe"), "CraftingSystem should expose has_recipe")
	assert(crafting_system.has_recipe("recipe_bandage_basic"), "recipe_bandage_basic should load from data/recipes")
	assert(crafting_system.has_recipe("recipe_repair_weapon_basic"), "repair recipe should load from data/recipes")


static func _test_unlocks_default_recipes() -> void:
	var crafting_system := _get_autoload("CraftingSystem")
	assert(crafting_system != null, "CraftingSystem autoload should exist")
	assert(
		crafting_system.is_recipe_unlocked("recipe_bandage_basic"),
		"Default unlocked recipe should be available immediately"
	)

	var preview: Dictionary = crafting_system.preview_craft("recipe_bandage_basic")
	assert(str(preview.get("output_item", "")) == "1006", "Bandage recipe should output item 1006")


static func _test_marks_repair_recipes() -> void:
	var crafting_system := _get_autoload("CraftingSystem")
	assert(crafting_system != null, "CraftingSystem autoload should exist")
	var recipe: Dictionary = crafting_system.get_recipe("recipe_repair_weapon_basic")
	assert(bool(recipe.get("is_repair", false)), "Repair recipe should retain is_repair flag")
	assert(int(recipe.get("repair_amount", 0)) == 30, "Repair recipe should retain repair amount")


static func _get_autoload(node_name: String) -> Node:
	var loop := Engine.get_main_loop()
	if not (loop is SceneTree):
		return null
	var tree: SceneTree = loop
	if tree.root == null:
		return null
	return tree.root.get_node_or_null(node_name)
