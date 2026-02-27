extends BaseModule
# BaseBuildingModule - 基地建设系统

signal structure_built(structure_id: String, position: Vector2)
signal structure_upgraded(structure_id: String, level: int)

const STRUCTURES = {
	"workbench": {
		"name": "工作台",
		"cost": {"wood": 5, "metal": 2},
		"benefits": ["解锁制作功能"]
	},
	"bed": {
		"name": "床铺",
		"cost": {"wood": 3, "cloth": 2},
		"benefits": ["可以睡觉存档", "恢复体力"]
	},
	"storage": {
		"name": "储物箱",
		"cost": {"wood": 4},
		"benefits": ["增加10个背包格子"]
	}
}

var built_structures: Array[Dictionary] = []
var base_level: int = 1

func can_build(structure_id: String):
	if not STRUCTURES.has(structure_id):
		return false
	
	var cost = STRUCTURES[structure_id].cost
	for material in cost:
		if not GameState.has_item(material, cost[material]):
			return false
	return true

func build_structure(structure_id: String, position: Vector2 = Vector2.ZERO):
	if not can_build(structure_id):
		return false
	
	var cost = STRUCTURES[structure_id].cost
	for material in cost:
		GameState.remove_item(material, cost[material])
	
	built_structures.append({
		"id": structure_id,
		"position": position,
		"level": 1
	})
	
	structure_built.emit(structure_id, position)
	return true

func has_structure(structure_id: String):
	for structure in built_structures:
		if structure.id == structure_id:
			return true
	return false

func get_structure_level(structure_id: String):
	for structure in built_structures:
		if structure.id == structure_id:
			return structure.level
	return 0

func upgrade_structure(structure_id: String):
	for i in range(built_structures.size()):
		if built_structures[i].id == structure_id:
			built_structures[i].level += 1
			structure_upgraded.emit(structure_id, built_structures[i].level)
			return true
	return false

func get_available_structures() -> Array[Dictionary]:
	var available = []
	for id in STRUCTURES:
		available.append({
			"id": id,
			"name": STRUCTURES[id].name,
			"can_build": can_build(id),
			"already_built": has_structure(id)
		})
	return available

func sleep_at_base():
	# 恢复玩家状态
	GameState.player_hp = GameState.player_max_hp
	GameState.player_mental = 100
	GameState.player_stamina = 100
	
	# 保存游戏
	SaveSystem.save_game()
	
	EventBus.emit(EventBus.EventType.GAME_SAVED, {})
