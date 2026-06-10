extends RefCounted

const CraftingRunner = preload("res://scripts/core/crafting/crafting_runner.gd")
const EconomyTransactions = preload("res://scripts/core/economy/economy_transactions.gd")

var _crafting_runner := CraftingRunner.new()
var _economy_transactions := EconomyTransactions.new()


func validate_recipe(simulation: RefCounted, progression_rules: RefCounted, actor_id: int, recipe_id: String, recipe_library: Dictionary, crafting_context: Dictionary = {}) -> Dictionary:
	return _crafting_runner.validate_craft_recipe(simulation, progression_rules, actor_id, recipe_id, recipe_library, crafting_context)


func craft_recipe(simulation: RefCounted, progression_rules: RefCounted, actor_id: int, recipe_id: String, recipe_library: Dictionary, crafting_context: Dictionary = {}) -> Dictionary:
	return _crafting_runner.craft_recipe(simulation, progression_rules, actor_id, recipe_id, recipe_library, crafting_context)


func deconstruct_actor_item(simulation: RefCounted, actor_id: int, item_id: String, count: int, item_library: Dictionary = {}) -> Dictionary:
	return _economy_transactions.deconstruct_actor_item(simulation, actor_id, item_id, count, item_library)
