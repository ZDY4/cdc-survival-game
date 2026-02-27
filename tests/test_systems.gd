extends SceneTree
# TestRunner - 系统测试脚本
# 测试所有新系统的基本功能

func _init():
	print("=== CDC 生存游戏系统测试 ===\n")
	
	var passed = 0
	var failed = 0
	
	# 测试1: SurvivalStatusSystem
	print("[测试1] 生存状态系统...")
	if _test_survival_status():
		print("✓ 通过")
		passed += 1
	else:
		print("✗ 失败")
		failed += 1
	
	# 测试2: ScavengeSystem
	print("\n[测试2] 搜刮系统...")
	if _test_scavenge():
		print("✓ 通过")
		passed += 1
	else:
		print("✗ 失败")
		failed += 1
	
	# 测试3: EncounterSystem
	print("\n[测试3] 遭遇系统...")
	if _test_encounter():
		print("✓ 通过")
		passed += 1
	else:
		print("✗ 失败")
		failed += 1
	
	# 测试4: ItemDurabilitySystem
	print("\n[测试4] 物品耐久系统...")
	if _test_durability():
		print("✓ 通过")
		passed += 1
	else:
		print("✗ 失败")
		failed += 1
	
	# 测试5: StoryClueSystem
	print("\n[测试5] 环境叙事系统...")
	if _test_story_clue():
		print("✓ 通过")
		passed += 1
	else:
		print("✗ 失败")
		failed += 1
	
	# 总结
	print("\n=== 测试结果 ===")
	print("通过: %d / %d" % [passed, passed + failed])
	
	if failed == 0:
		print("所有测试通过！")
	else:
		print("有 %d 个测试失败" % failed)
	
	quit()

func _test_survival_status() -> bool:
	var system = load("res://systems/survival_status_system.gd")
	if not system:
		return false
	
	# 测试体温范围
	if system.TEMP_NORMAL_MIN != 35.0:
		return false
	if system.TEMP_NORMAL_MAX != 39.0:
		return false
	
	# 测试免疫力范围
	if system.IMMUNITY_MAX != 100.0:
		return false
	
	return true

func _test_scavenge() -> bool:
	var system = load("res://systems/scavenge_system.gd")
	if not system:
		return false
	
	# 测试搜索时间枚举
	if system.SearchTime.QUICK != 2:
		return false
	if system.SearchTime.STANDARD != 4:
		return false
	if system.SearchTime.THOROUGH != 6:
		return false
	
	# 测试工具配置
	if not system.TOOL_STATS.has("crowbar"):
		return false
	
	return true

func _test_encounter() -> bool:
	var system = load("res://systems/encounter_system.gd")
	var database = load("res://data/encounters/encounter_database.gd")
	
	if not system or not database:
		return false
	
	# 测试遭遇数量
	var encounters = database.get_all_encounters()
	if encounters.size() < 15:
		print("  警告: 遭遇事件数量不足 (%d/15)" % encounters.size())
	
	# 测试技能检定公式存在
	var temp_system = system.new()
	if not temp_system.has_method("perform_skill_check"):
		return false
	
	return true

func _test_durability() -> bool:
	var system = load("res://systems/item_durability_system.gd")
	if not system:
		return false
	
	# 测试耐久数据库
	if not system.ITEM_DURABILITY_DATA.has("crowbar"):
		return false
	if not system.ITEM_DURABILITY_DATA.has("kevlar_vest"):
		return false
	
	# 测试维修材料配置
	if not system.REPAIR_MATERIALS.has("weapon"):
		return false
	
	return true

func _test_story_clue() -> bool:
	var system = load("res://systems/story_clue_system.gd")
	if not system:
		return false
	
	# 测试线索数据库
	if not system.CLUE_DATABASE.has("diary_doctor_1"):
		return false
	
	# 测试章节配置
	if not system.STORY_CHAPTERS.has("conspiracy"):
		return false
	
	# 测试线索数量
	if system.CLUE_DATABASE.size() < 20:
		print("  警告: 线索数量不足 (%d/20)" % system.CLUE_DATABASE.size())
	
	return true
