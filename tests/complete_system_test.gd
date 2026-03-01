extends Node
# CompleteSystemTest - 完整系统测试
# 测试所有新功能

signal test_completed(results: Dictionary)

var _test_results: Dictionary = {}
var _current_test: String = ""

func _ready():
	print("\n" + "=".repeat(70))
	print("  完整系统测试 - 所有功能验证")
	print("=".repeat(70) + "\n")
	
	await get_tree().create_timer(0.5).timeout
	await _run_all_tests()
	_show_final_results()

func _run_all_tests():
	# Phase 1: 负重系统
	await _test_carry_system()
	
	# Phase 2: 统一装备
	await _test_unified_equipment()
	
	# Phase 3: 新敌人
	await _test_new_enemies()
	
	# Phase 4: 战斗惩罚
	await _test_combat_penalty()
	
	# Phase 5: 音频系统
	await _test_audio_system()
	
	# Phase 6: UI显示
	await _test_ui_display()

func _test_carry_system():
	print("[Phase 1/6] 负重系统测试...")
	
	var result = {"success": true, "tests": {}}
	
	# 测试1: 基础重量计算
	GameState.inventory_items.clear()
	CarrySystem.on_inventory_changed()
	
	if CarrySystem.get_current_weight() != 0.0:
		result.success = false
		result.tests.basic = "初始重量不为0"
	else:
		result.tests.basic = "✅"
	
	# 测试2: 超重判断
	var max_weight = CarrySystem.get_max_carry_weight()
	var overload_items = int(max_weight / 3.5) + 15
	for i in range(overload_items):
		GameState.add_item("rifle", 1)
	CarrySystem.on_inventory_changed()
	
	if CarrySystem.can_carry_item("rifle", 1):
		result.success = false
		result.tests.overload = "超重时应拒绝携带"
	else:
		result.tests.overload = "✅"
	
	_record_result("负重系统", result)

func _test_unified_equipment(level: int = 1):
	print("[Phase 2/6] 统一装备系统测试...")
	
	var result = {"success": true, "tests": {}}
	
	# 测试装备武器
	if UnifiedEquipmentSystem:
		var equip_result = UnifiedEquipmentSystem.equip("knife", "main_hand")
		if not equip_result:
			result.success = false
			result.tests.equip = "装备失败"
		else:
			result.tests.equip = "✅"
		
		# 测试战斗属性计算
		var stats = UnifiedEquipmentSystem.calculate_combat_stats()
		if stats.damage <= 0:
			result.success = false
			result.tests.stats = "战斗属性计算错误"
		else:
			result.tests.stats = "✅"
	else:
		result.success = false
		result.tests.exists = "系统不存在"
	
	_record_result("统一装备", result)

func _test_new_enemies():
	print("[Phase 3/6] 新敌人测试...")
	
	var result = {"success": true, "tests": {}}
	
	# 测试变异狗
	if EnemyDatabase:
		var dog = EnemyDatabase.get_enemy("mutant_dog")
		if dog.is_empty():
			result.tests.mutant_dog = "⚠️ 未添加到数据库"
		else:
			result.tests.mutant_dog = "✅"
		
		# 测试掠夺者
		var raider = EnemyDatabase.get_enemy("raider")
		if raider.is_empty():
			result.tests.raider = "⚠️ 未添加到数据库"
		else:
			result.tests.raider = "✅"
	else:
		result.success = false
		result.tests.exists = "EnemyDatabase不存在"
	
	_record_result("新敌人", result)

func _test_combat_penalty():
	print("[Phase 4/6] 战斗惩罚测试...")
	
	var result = {"success": true, "tests": {}}
	
	if CombatPenaltySystem:
		# 测试惩罚计算
		var penalty = CombatPenaltySystem.get_dodge_penalty()
		if penalty < 0:
			result.success = false
			result.tests.penalty = "惩罚值异常"
		else:
			result.tests.penalty = "✅"
		
		# 测试描述
		var desc = CombatPenaltySystem.get_penalty_description()
		if desc.is_empty():
			result.tests.description = "描述为空"
		else:
			result.tests.description = "✅"
	else:
		result.success = false
		result.tests.exists = "系统不存在"
	
	_record_result("战斗惩罚", result)

func _test_audio_system():
	print("[Phase 5/6] 音频系统测试...")
	
	var result = {"success": true, "tests": {}}
	
	if AudioSystem:
		# 测试设置
		AudioSystem.set_master_volume(0.8)
		if AudioSystem.master_volume != 0.8:
			result.success = false
			result.tests.volume = "音量设置失败"
		else:
			result.tests.volume = "✅"
		
		result.tests.exists = "✅"
	else:
		result.success = false
		result.tests.exists = "系统不存在"
	
	_record_result("音频系统", result)

func _test_ui_display():
	print("[Phase 6/6] UI显示测试...")
	
	var result = {"success": true, "tests": {}}
	
	# 测试InventoryUI是否存在
	if FileAccess.file_exists("res://scenes/ui/inventory_ui.tscn"):
		result.tests.inventory_ui = "✅"
	else:
		result.tests.inventory_ui = "⚠️ 场景文件不存在"
	
	# 测试脚本是否存在
	if FileAccess.file_exists("res://scripts/ui/inventory_ui.gd"):
		result.tests.inventory_script = "✅"
	else:
		result.tests.inventory_script = "⚠️ 脚本不存在"
	
	_record_result("UI显示", result)

func _record_result():
	_test_results[test_name] = result
	
	if result.success:
		print("  ✅ " + test_name + " 通过")
	else:
		print("  ❌ " + test_name + " 失败")
		for key in result.tests.keys():
			if result.tests[key] != "✅":
				print("    - " + key + ": " + result.tests[key])

func _show_final_results():
	print("\n" + "=".repeat(70))
	print("  最终测试结果")
	print("=".repeat(70))
	
	var total = _test_results.size()
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
	
	print("\n总计: " + str(total) + ", 通过: " + str(passed) + ", 失败: " + str(failed))
	
	if failed == 0:
		print("\n🎉 所有测试通过！系统运行正常！")
	else:
		print("\n⚠️ 有 " + str(failed) + " 个测试失败，需要修复")
	
	print("=".repeat(70) + "\n")
	
	# 退出
	await get_tree().create_timer(2.0).timeout
	if failed == 0:
		get_tree().quit(0)
	else:
		get_tree().quit(1)
