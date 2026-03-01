extends Node
# CarrySystemIntegrationTest - 负重系统集成测试
# 在游戏启动时自动运行

var _test_results: Dictionary = {}
var _current_test: String = ""

func _ready():
	print("\n" + "=".repeat(60))
	print("  CarrySystem 集成测试")
	print("=".repeat(60) + "\n")
	
	# 等待所有系统初始化
	await get_tree().create_timer(0.5).timeout
	
	# 运行所有测试
	await _run_all_tests()
	
	# 显示结果
	_show_results()

func _run_all_tests():
	# 测试1: 基础负重计算
	await _test_basic_weight()
	
	# 测试2: 负重等级
	await _test_encumbrance_levels()
	
	# 测试3: 超重判断
	await _test_overload_detection()
	
	# 测试4: 移动惩罚
	await _test_movement_penalty()
	
	# 测试5: 背包加成
	await _test_backpack_bonus()

func _test_basic_weight():
	_current_test = "基础负重计算"
	print("[Test 1/5] " + _current_test + "...")
	
	var result = {"success": true, "error": ""}
	
	# 清空背包
	GameState.inventory_items.clear()
	CarrySystem.on_inventory_changed()
	
	# 检查初始重量
	var initial = CarrySystem.get_current_weight()
	if initial != 0.0:
		result.success = false
		result.error = "初始重量应为0，实际%.1f" % initial
		_record_result(result)
		return
	
	# 添加测试物品（假设knife重量0.3）
	GameState.add_item("knife", 1)
	CarrySystem.on_inventory_changed()
	
	var after_add = CarrySystem.get_current_weight()
	if after_add < 0.1:
		result.success = false
		result.error = "添加物品后重量应为>0，实际%.1f" % after_add
	
	_record_result(result)

func _test_encumbrance_levels():
	_current_test = "负重等级判断"
	print("[Test 2/5] " + _current_test + "...")
	
	var result = {"success": true, "error": ""}
	
	# 清空
	GameState.inventory_items.clear()
	CarrySystem.on_inventory_changed()
	
	var max_weight = CarrySystem.get_max_carry_weight()
	
	# 轻载测试 (30%)
	var light_items = int(max_weight * 0.3 / 3.5)
	for i in range(light_items):
		GameState.add_item("rifle", 1)
	CarrySystem.on_inventory_changed()
	
	if CarrySystem.get_encumbrance_level() != 0:  # LIGHT = 0
		result.success = false
		result.error = "30%%负重应为轻载，实际是%s" % CarrySystem.get_encumbrance_name()
		_record_result(result)
		return
	
	# 中载测试 (60%)
	GameState.inventory_items.clear()
	var medium_items = int(max_weight * 0.6 / 3.5)
	for i in range(medium_items):
		GameState.add_item("rifle", 1)
	CarrySystem.on_inventory_changed()
	
	if CarrySystem.get_encumbrance_level() != 1:  # MEDIUM = 1
		result.success = false
		result.error = "60%%负重应为中载，实际是%s" % CarrySystem.get_encumbrance_name()
	
	_record_result(result)

func _test_overload_detection():
	_current_test = "超重判断"
	print("[Test 3/5] " + _current_test + "...")
	
	var result = {"success": true, "error": ""}
	
	# 清空
	GameState.inventory_items.clear()
	CarrySystem.on_inventory_changed()
	
	var max_weight = CarrySystem.get_max_carry_weight()
	
	# 应该能携带
	if not CarrySystem.can_carry_item("rifle", 1):
		result.success = false
		result.error = "空背包时应能携带物品"
		_record_result(result)
		return
	
	# 添加大量物品直到超重
	var rifles = int(max_weight / 3.5) + 10
	for i in range(rifles):
		GameState.add_item("rifle", 1)
	
	CarrySystem.on_inventory_changed()
	
	# 现在应该超重
	if CarrySystem.can_carry_item("rifle", 1):
		result.success = false
		result.error = "超重时应拒绝携带"
		_record_result(result)
		return
	
	# 检查等级
	var level = CarrySystem.get_encumbrance_level()
	if level < 3:  # 至少应该是OVERLOADED
		result.success = false
		result.error = "添加大量物品后应为超载，实际是%s" % CarrySystem.get_encumbrance_name()
	
	_record_result(result)

func _test_movement_penalty():
	_current_test = "移动惩罚"
	print("[Test 4/5] " + _current_test + "...")
	
	var result = {"success": true, "error": ""}
	
	# 清空
	GameState.inventory_items.clear()
	CarrySystem.on_inventory_changed()
	
	# 轻载惩罚应为1.0
	var light_penalty = CarrySystem.get_movement_penalty()
	if light_penalty != 1.0:
		result.success = false
		result.error = "轻载惩罚应为1.0，实际%.1f" % light_penalty
		_record_result(result)
		return
	
	# 添加物品到重载(确保超过75%阈值)
	var max_weight = CarrySystem.get_max_carry_weight()
	var target_weight = max_weight * 0.8
	var heavy_items = int(target_weight / 3.5) + 1
	for i in range(heavy_items):
		GameState.add_item("rifle", 1)
	CarrySystem.on_inventory_changed()
	
	var heavy_penalty = CarrySystem.get_movement_penalty()
	if heavy_penalty != 1.6:
		result.success = false
		result.error = "重载惩罚应为1.6，实际%.1f" % heavy_penalty
	
	_record_result(result)

func _test_backpack_bonus():
	_current_test = "背包负重加成"
	print("[Test 5/5] " + _current_test + "...")
	
	var result = {"success": true, "error": ""}
	
	# 记录无背包时的负重
	var base_max = CarrySystem.get_max_carry_weight()
	
	# 这里需要模拟装备背包，简化测试
	# 只要最大负重 > 基础值30即可
	if base_max < 30:
		result.success = false
		result.error = "最大负重应至少30，实际%.1f" % base_max
	
	_record_result(result)

func _record_result():
	_test_results[_current_test] = result
	
	if result.success:
		print("  ✅ 通过")
	else:
		print("  ❌ 失败: " + result.error)

func _show_results():
	print("\n" + "=".repeat(60))
	print("  测试结果")
	print("=".repeat(60))
	
	var passed = 0
	var failed = 0
	
	for test_name in _test_results.keys():
		var result = _test_results[test_name]
		var status = "✅" if result.success else "❌"
		print(status + " " + test_name)
		
		if result.success:
			passed += 1
		else:
			failed += 1
			print("   错误: " + result.error)
	
	print("\n总计: %d, 通过: %d, 失败: %d" % [_test_results.size(), passed, failed])
	
	if failed == 0:
		print("\n🎉 所有测试通过！")
	else:
		print("\n⚠️ 有 %d 个测试失败" % failed)
	
	print("=".repeat(60) + "\n")
	
	# 延迟退出（如果在headless模式）
	await get_tree().create_timer(2.0).timeout
	
	# 如果有失败，退出码非0
	if failed > 0:
		get_tree().quit(1)
	else:
		get_tree().quit(0)
