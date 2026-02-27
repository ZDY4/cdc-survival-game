extends BaseModule
# CraftingModule - 制作系统

const CRAFTING_RECIPES = {
	"bandage": {
		"name": "绷带",
		"materials": {"cloth": 2},
		"result": {"item": "bandage", "count": 1}
	},
	"spear": {
		"name": "长矛",
		"materials": {"wood": 3, "metal": 1},
		"result": {"item": "spear", "count": 1}
	}
}

func can_craft(recipe_id: String):
	if not CRAFTING_RECIPES.has(recipe_id):
		return false
	
	var recipe = CRAFTING_RECIPES[recipe_id]
	for material_id in recipe.materials:
		var required = recipe.materials[material_id]
		if not GameState.has_item(material_id, required):
			return false
	return true

func craft(recipe_id: String):
	if not can_craft(recipe_id):
		return false
	
	var recipe = CRAFTING_RECIPES[recipe_id]
	
	# 消耗材料
	for material_id in recipe.materials:
		var required = recipe.materials[material_id]
		GameState.remove_item(material_id, required)
	
	# 获得产物
	var result = recipe.result
	GameState.add_item(result.item, result.count)
	
	EventBus.emit(EventBus.EventType.CRAFTING_COMPLETED, {
		"recipe": recipe_id,
		"result": result
	})
	
	return true

func get_available_recipes() -> Array[Dictionary]:
	var available = []
	for recipe_id in CRAFTING_RECIPES:
		available.append({
			"id": recipe_id,
			"name": CRAFTING_RECIPES[recipe_id].name,
			"can_craft": can_craft(recipe_id)
		})
	return available
