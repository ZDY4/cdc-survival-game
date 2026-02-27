extends BaseModule
## InventoryModule - 背包模块
## 提供背包管理的高层接口，实际数据存储在GameState

# ========== 信号 ==========
signal item_added(item_id: String, count: int, total: int)
signal item_removed(item_id: String, count: int, remaining: int)
signal item_used(item_id: String, success: bool)
signal weight_changed(current_weight: float, max_weight: float)

# ========== 公共 API ==========

## 添加物品到背包
func add_item(item_id: String, count: int = 1) -> bool:
	if not GameState:
		push_error("[InventoryModule] GameState not found")
		return false
	
	# 验证物品是否存在
	if not ItemDatabase.has_item(item_id):
		push_warning("[InventoryModule] 物品不存在: %s" % item_id)
		return false
	
	# 检查重量限制
	var item_weight = ItemDatabase.get_item_weight(item_id)
	var total_weight = get_inventory_weight() + (item_weight * count)
	var max_weight = get_max_weight()
	
	if total_weight > max_weight:
		push_warning("[InventoryModule] 超重，无法添加物品")
		return false
	
	# 添加到GameState
	var result = GameState.add_item(item_id, count)
	
	if result:
		var current_count = GameState.get_item_count(item_id)
		item_added.emit(item_id, count, current_count)
		weight_changed.emit(get_inventory_weight(), max_weight)
	
	return result

## 从背包移除物品
func remove_item(item_id: String, count: int = 1) -> bool:
	if not GameState:
		return false
	
	var result = GameState.remove_item(item_id, count)
	
	if result:
		var remaining = GameState.get_item_count(item_id)
		item_removed.emit(item_id, count, remaining)
		weight_changed.emit(get_inventory_weight(), get_max_weight())
	
	return result

## 使用物品
func use_item(item_id: String) -> bool:
	if not GameState:
		return false
	
	if not GameState.has_item(item_id):
		item_used.emit(item_id, false)
		return false
	
	var item_data = ItemDatabase.get_item(item_id)
	if item_data.is_empty():
		item_used.emit(item_id, false)
		return false
	
	# 检查是否可使用
	if not item_data.get("usable", false):
		push_warning("[InventoryModule] 该物品不可使用: %s" % item_id)
		item_used.emit(item_id, false)
		return false
	
	# 应用消耗品效果
	var consumable_data = item_data.get("consumable_data", {})
	var effects = consumable_data.get("effects", {})
	
	var success = _apply_consumable_effects(effects)
	
	if success:
		# 消耗物品
		GameState.remove_item(item_id, 1)
		var remaining = GameState.get_item_count(item_id)
		item_removed.emit(item_id, 1, remaining)
	
	item_used.emit(item_id, success)
	return success

## 检查是否有物品
func has_item(item_id: String, count: int = 1) -> bool:
	if not GameState:
		return false
	return GameState.has_item(item_id, count)

## 获取物品数量
func get_item_count(item_id: String) -> int:
	if not GameState:
		return 0
	return GameState.get_item_count(item_id)

## 获取背包中的所有物品
func get_items() -> Array[Dictionary]:
	if not GameState:
		return []
	return GameState.inventory_items.duplicate()

## 获取物品名称
func get_item_display_name(item_id: String) -> String:
	return ItemDatabase.get_item_name(item_id)

## 获取物品图标路径
func get_item_icon(item_id: String) -> String:
	var item = ItemDatabase.get_item(item_id)
	return item.get("icon_path", "")

# ========== 重量系统 ==========

## 获取当前背包重量
func get_inventory_weight() -> float:
	if not GameState:
		return 0.0
	
	var total = 0.0
	for item in GameState.inventory_items:
		var item_id = item.get("id", "")
		var count = item.get("count", 1)
		total += ItemDatabase.get_item_weight(item_id) * count
	
	return total

## 获取最大负重
func get_max_weight() -> float:
	# 基础负重 + 装备提供的负重
	var base_weight = 50.0  # 基础负重50kg
	
	# 检查装备系统提供的额外负重
	if UnifiedEquipmentSystem:
		var carry_bonus = UnifiedEquipmentSystem.calculate_combat_stats().get("carry_bonus", 0.0)
		base_weight += carry_bonus
	
	return base_weight

## 获取当前负重百分比
func get_weight_percentage() -> float:
	var current = get_inventory_weight()
	var max_w = get_max_weight()
	if max_w <= 0:
		return 0.0
	return (current / max_w) * 100.0

## 检查是否超重
func is_overweight() -> bool:
	return get_inventory_weight() > get_max_weight()

## 获取剩余负重空间
func get_remaining_weight() -> float:
	return get_max_weight() - get_inventory_weight()

## 检查是否能装下指定重量的物品
func can_carry(weight: float) -> bool:
	return (get_inventory_weight() + weight) <= get_max_weight()

# ========== 分类查询 ==========

## 获取所有消耗品
func get_consumables() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var items = get_items()
	
	for item in items:
		var item_id = item.get("id", "")
		if ItemDatabase.is_consumable(item_id):
			result.append(item)
	
	return result

## 获取所有武器装备
func get_equipment() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var items = get_items()
	
	for item in items:
		var item_id = item.get("id", "")
		if ItemDatabase.is_equippable(item_id):
			result.append(item)
	
	return result

## 获取所有材料
func get_materials() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var items = get_items()
	
	for item in items:
		var item_id = item.get("id", "")
		if ItemDatabase.get_item_type(item_id) == "material":
			result.append(item)
	
	return result

# ========== 批量操作 ==========

## 添加多个物品
func add_items(items: Array[Dictionary]) -> Dictionary:
	var results = {
		"success": [],
		"failed": []
	}
	
	for item_data in items:
		var item_id = item_data.get("id", "")
		var count = item_data.get("count", 1)
		
		if add_item(item_id, count):
			results.success.append(item_id)
		else:
			results.failed.append(item_id)
	
	return results

## 移除多个物品
func remove_items(items: Array[Dictionary]) -> Dictionary:
	var results = {
		"success": [],
		"failed": []
	}
	
	for item_data in items:
		var item_id = item_data.get("id", "")
		var count = item_data.get("count", 1)
		
		if remove_item(item_id, count):
			results.success.append(item_id)
		else:
			results.failed.append(item_id)
	
	return results

## 清除背包（用于死亡惩罚等）
func clear_inventory():
	if not GameState:
		return
	
	GameState.inventory_items.clear()
	weight_changed.emit(0.0, get_max_weight())
	print("[InventoryModule] 背包已清空")

# ========== 私有方法 ==========

func _apply_consumable_effects(effects: Dictionary) -> bool:
	if effects.is_empty():
		return false
	
	var applied = false
	
	if effects.has("heal"):
		GameState.heal_player(effects.heal)
		applied = true
	
	if effects.has("hunger"):
		GameState.player_hunger = mini(100, GameState.player_hunger + effects.hunger)
		applied = true
	
	if effects.has("thirst"):
		GameState.player_thirst = mini(100, GameState.player_thirst + effects.thirst)
		applied = true
	
	if effects.has("stamina"):
		GameState.player_stamina = mini(100, GameState.player_stamina + effects.stamina)
		applied = true
	
	if effects.has("mental"):
		GameState.player_mental = mini(100, GameState.player_mental + effects.mental)
		applied = true
	
	return applied

# ========== 调试 ==========

func debug_print_inventory():
	print("=== 背包内容 ===")
	var items = get_items()
	print("物品数量: %d" % items.size())
	print("总重量: %.1f / %.1f kg" % [get_inventory_weight(), get_max_weight()])
	
	for item in items:
		var item_id = item.get("id", "")
		var count = item.get("count", 1)
		var name = ItemDatabase.get_item_name(item_id)
		var weight = ItemDatabase.get_item_weight(item_id) * count
		print("  %s x%d (%.1f kg)" % [name, count, weight])
