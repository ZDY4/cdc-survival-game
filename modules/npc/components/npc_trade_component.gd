extends Node
## NPC交易组件
## 处理交易逻辑、价格计算、库存管理

class_name NPCTradeComponent

const NPCBase = preload("res://modules/npc/npc_base.gd")

signal trade_opened
signal trade_closed
signal item_bought(item_id: String, count: int, price: int)
signal item_sold(item_id: String, count: int, price: int)
signal trade_completed(profit: int)

var npc: NPCBase
var trade_ui: Control = null

func initialize(parent_npc: NPCBase):
	npc = parent_npc

## 打开交易界面
func open_trade_ui() -> bool:
	if not npc or not npc.npc_data:
		return false
	
	if not npc.can_trade():
		return false
	
	# 创建交易UI
	if not FileAccess.file_exists("res://modules/npc/ui/npc_trade_ui.tscn"):
		push_warning("[NPCTradeComponent] 交易UI场景不存在，跳过创建UI")
		return false
	
	var ui_scene = load("res://modules/npc/ui/npc_trade_ui.tscn")
	if not ui_scene:
		push_error("[NPCTradeComponent] 无法加载交易UI场景")
		return false
	
	trade_ui = ui_scene.instantiate()
	if trade_ui.has_method("initialize"):
		trade_ui.call("initialize", self, npc.npc_data)
	
	get_tree().current_scene.add_child(trade_ui)
	
	trade_opened.emit()
	
	# 等待交易结束
	await trade_ui.trade_finished
	
	var profit = trade_ui.total_profit
	trade_completed.emit(profit)
	
	trade_ui.queue_free()
	trade_ui = null
	
	trade_closed.emit()
	
	return true

## 计算购买价格（NPC卖给玩家）
func calculate_buy_price(item_id: String, base_price: int) -> int:
	if not npc or not npc.npc_data:
		return base_price
	
	var npc_data = npc.npc_data
	
	# 基础价格倍率
	var multiplier = npc_data.trade_data.buy_price_modifier
	
	# 魅力影响（每点魅力降低2%价格）
	var player_charisma = _get_player_charisma()
	var charisma_bonus = (player_charisma - 10) * 0.02
	
	# 友好度影响（每点友好度降低1%价格）
	var friendliness_bonus = (npc_data.mood.friendliness - 50) * 0.01
	
	# 信任度影响
	var trust_bonus = (npc_data.mood.trust - 50) * 0.005
	
	# 计算最终倍率
	var final_multiplier = multiplier - charisma_bonus - friendliness_bonus - trust_bonus
	final_multiplier = clamp(final_multiplier, 0.3, 3.0)  # 限制在30%-300%
	
	return int(base_price * final_multiplier)

## 计算出售价格（NPC从玩家购买）
func calculate_sell_price(item_id: String, base_price: int) -> int:
	if not npc or not npc.npc_data:
		return base_price
	
	var npc_data = npc.npc_data
	
	# 基础价格倍率
	var multiplier = npc_data.trade_data.sell_price_modifier
	
	# 魅力影响（每点魅力提高2%售价）
	var player_charisma = _get_player_charisma()
	var charisma_bonus = (player_charisma - 10) * 0.02
	
	# 友好度影响（每点友好度提高0.5%售价）
	var friendliness_bonus = (npc_data.mood.friendliness - 50) * 0.005
	
	# 计算最终倍率
	var final_multiplier = multiplier + charisma_bonus + friendliness_bonus
	final_multiplier = clamp(final_multiplier, 0.1, 2.0)  # 限制在10%-200%
	
	return int(base_price * final_multiplier)

## 检查是否可以购买
func can_buy_item(item_id: String, count: int) -> bool:
	if not npc or not npc.npc_data:
		return false
	
	var inventory = npc.npc_data.trade_data.inventory
	
	for item in inventory:
		if item.id == item_id and item.count >= count:
			return true
	
	return false

## 执行购买
func buy_item(item_id: String, count: int) -> Dictionary:
	var result = {"success": false, "reason": ""}
	
	if not can_buy_item(item_id, count):
		result.reason = "NPC没有足够的该物品"
		return result
	
	# 获取价格
	var base_price = _get_item_base_price(item_id)
	var price_per_item = calculate_buy_price(item_id, base_price)
	var total_price = price_per_item * count
	
	# 检查玩家货币（假设使用物品作为货币）
	if not _can_player_afford(total_price):
		result.reason = "没有足够的资金"
		return result
	
	# 扣除玩家货币
	_deduct_player_currency(total_price)
	
	# 从NPC库存移除
	_remove_from_npc_inventory(item_id, count)
	
	# 添加到玩家背包
	if InventoryModule:
		InventoryModule.add_item(item_id, count)
	
	# 增加NPC货币
	_add_npc_money(total_price)
	
	# 增加交易次数
	npc.npc_data.trade_data.trade_count_today += count
	
	# 影响情绪（交易增加友好度）
	npc.change_mood("friendliness", 1)
	
	result.success = true
	result.price = total_price
	
	item_bought.emit(item_id, count, total_price)
	
	print("[NPCTradeComponent] 玩家从NPC %s 购买了 %s x%d，花费 %d" % [
		npc.npc_name, item_id, count, total_price
	])
	
	return result

## 执行出售
func sell_item(item_id: String, count: int) -> Dictionary:
	var result = {"success": false, "reason": ""}
	
	# 检查玩家是否有该物品
	if InventoryModule and not InventoryModule.has_item(item_id, count):
		result.reason = "你没有足够的该物品"
		return result
	
	# 获取价格
	var base_price = _get_item_base_price(item_id)
	var price_per_item = calculate_sell_price(item_id, base_price)
	var total_price = price_per_item * count
	
	# 检查NPC是否有足够货币
	if not _npc_has_money(total_price):
		result.reason = "%s没有足够的货币购买（需要 %d，当前 %d）" % [
			npc.npc_name if npc else "NPC", total_price, get_npc_money()
		]
		return result
	
	# 扣除NPC货币
	if not _deduct_npc_money(total_price):
		result.reason = "交易失败：无法扣除NPC货币"
		return result
	
	# 从玩家背包移除
	if InventoryModule:
		InventoryModule.remove_item(item_id, count)
	
	# 添加到NPC库存
	_add_to_npc_inventory(item_id, count, price_per_item)
	
	# 给予玩家货币
	_give_player_currency(total_price)
	
	# 影响情绪
	npc.change_mood("friendliness", 1)
	
	result.success = true
	result.price = total_price
	
	item_sold.emit(item_id, count, total_price)
	
	print("[NPCTradeComponent] 玩家向NPC %s 出售了 %s x%d，获得 %d" % [
		npc.npc_name, item_id, count, total_price
	])
	
	return result

## 获取NPC库存
func get_npc_inventory() -> Array:
	if not npc or not npc.npc_data:
		return []
	
	return npc.npc_data.trade_data.inventory.duplicate()

## 获取NPC货币
func get_npc_money() -> int:
	if not npc or not npc.npc_data:
		return 0
	return npc.npc_data.trade_data.money

## 设置NPC货币
func set_npc_money(amount: int):
	if not npc or not npc.npc_data:
		return
	npc.npc_data.trade_data.money = maxi(0, amount)

## 补货
func restock():
	if not npc or not npc.npc_data:
		return
	
	# 这里应该从配置加载默认库存
	print("[NPCTradeComponent] NPC %s 库存已补货" % npc.npc_name)

# ========== 私有方法 ==========

func _get_player_charisma() -> int:
	if GameState and GameState.has("player_charisma"):
		return GameState.player_charisma
	return 10

func _get_item_base_price(item_id: String) -> int:
	# 从物品数据库获取基础价格
	var data_manager = get_node_or_null("/root/DataManager")
	if data_manager:
		var item_data = data_manager.get_item_data(item_id)
		if item_data and item_data.has("value"):
			return item_data.value
	
	# 默认价格
	return 10

func _can_player_afford(amount: int) -> bool:
	if GameState:
		return GameState.has_money(amount)
	return false

func _deduct_player_currency(amount: int) -> bool:
	if GameState:
		return GameState.remove_money(amount)
	return false

func _give_player_currency(amount: int) -> bool:
	if GameState:
		return GameState.add_money(amount)
	return false

func _remove_from_npc_inventory(item_id: String, count: int):
	if not npc or not npc.npc_data:
		return
	
	var inventory = npc.npc_data.trade_data.inventory
	for i in range(inventory.size()):
		if inventory[i].id == item_id:
			inventory[i].count -= count
			if inventory[i].count <= 0:
				inventory.remove_at(i)
			break

func _add_to_npc_inventory(item_id: String, count: int, price: int):
	if not npc or not npc.npc_data:
		return
	
	var inventory = npc.npc_data.trade_data.inventory
	
	# 检查是否已存在
	for item in inventory:
		if item.id == item_id:
			item.count += count
			return
	
	# 添加新物品
	inventory.append({
		"id": item_id,
		"count": count,
		"price": price
	})

# ========== NPC货币管理方法 ==========

func _npc_has_money(amount: int) -> bool:
	if not npc or not npc.npc_data:
		return false
	return npc.npc_data.trade_data.money >= amount

func _deduct_npc_money(amount: int) -> bool:
	if not npc or not npc.npc_data:
		return false
	if npc.npc_data.trade_data.money < amount:
		return false
	npc.npc_data.trade_data.money -= amount
	return true

func _add_npc_money(amount: int) -> bool:
	if not npc or not npc.npc_data:
		return false
	npc.npc_data.trade_data.money += amount
	return true
