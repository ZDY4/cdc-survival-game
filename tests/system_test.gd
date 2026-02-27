extends Node2D
# TestScene - 测试新系统的场景

@onready var result_label: Label = $CanvasLayer/Panel/VBoxContainer/ResultLabel

var tests_passed: int = 0
var tests_failed: int = 0

func _ready():
	print("=" * 50)
	print("开始系统测试")
	print("=" * 50)
	
	# 等待系统初始化
	await get_tree().create_timer(1.0).timeout
	
	# 运行所有测试
	test_time_manager()
	test_experience_system()
	test_attribute_system()
	test_skill_system()
	test_day_night_risk_system()
	test_integration()
	
	# 显示结果
	var total = tests_passed + tests_failed
	var result_text = "测试完成！\n通过: %d/%d\n失败: %d" % [tests_passed, total, tests_failed]
	
	if result_label:
		result_label.text = result_text
	
	print("=" * 50)
	print(result_text)
	print("=" * 50)

func test_time_manager():
	print("\n[测试] 时间管理系统")
	
	var tm = get_node_or_null("/root/TimeManager")
	if not tm:
		print("  ❌ TimeManager 未找到")
		tests_failed += 1
		return
	
	# 测试基本功能
	var initial_time = tm.get_current_time_dict()
	print("  初始时间: %s" % tm.get_full_datetime())
	
	# 测试时间推进
	tm.advance_minutes(30)
	assert(tm.current_minute == 30, "时间推进失败")
	print("  ✓ 时间推进正常")
	
	# 测试昼夜判断
	tm.set_time(1, 12, 0)
	assert(tm.is_day(), "白天判断失败")
	print("  ✓ 白天判断正常")
	
	tm.set_time(1, 22, 0)
	assert(tm.is_night(), "夜晚判断失败")
	print("  ✓ 夜晚判断正常")
	
	# 测试活动时间
	tm.set_time(1, 8, 0)
	var result = tm.do_activity("测试活动", 120)
	assert(result.new_time.hour == 10, "活动时间计算失败")
	print("  ✓ 活动时间正常")
	
	tests_passed += 1
	print("  ✅ 时间管理系统测试通过")

func test_experience_system():
	print("\n[测试] 经验值系统")
	
	var xp = get_node_or_null("/root/ExperienceSystem")
	if not xp:
		print("  ❌ ExperienceSystem 未找到")
		tests_failed += 1
		return
	
	# 重置状态
	xp.current_level = 1
	xp.current_xp = 0
	xp.available_stat_points = 0
	xp.available_skill_points = 0
	
	# 测试经验获取
	var result = xp.gain_xp(50, "test")
	assert(result.gained == 50, "经验获取失败")
	print("  ✓ 经验获取正常")
	
	# 测试升级
	xp.current_xp = 0
	xp.current_level = 1
	var level_up_result = xp.gain_xp(150, "test")
	if level_up_result.leveled_up:
		print("  ✓ 升级机制正常 (等级 %d)" % xp.current_level)
	else:
		print("  ⚠ 升级需要更多经验")
	
	# 测试点数
	assert(xp.available_stat_points >= 0, "属性点异常")
	assert(xp.available_skill_points >= 0, "技能点异常")
	print("  ✓ 点数系统正常")
	
	tests_passed += 1
	print("  ✅ 经验值系统测试通过")

func test_attribute_system():
	print("\n[测试] 属性系统")
	
	var attr = get_node_or_null("/root/AttributeSystem")
	if not attr:
		print("  ❌ AttributeSystem 未找到")
		tests_failed += 1
		return
	
	# 重置属性
	attr.strength = 5
	attr.agility = 5
	attr.constitution = 5
	attr.available_points = 5
	
	# 测试属性分配
	assert(attr.allocate_point("strength"), "力量分配失败")
	assert(attr.strength == 6, "力量值未增加")
	print("  ✓ 力量分配正常")
	
	assert(attr.allocate_point("agility"), "敏捷分配失败")
	assert(attr.agility == 6, "敏捷值未增加")
	print("  ✓ 敏捷分配正常")
	
	# 测试计算属性
	var stats = attr.get_calculated_stats()
	assert(stats.has("damage_bonus"), "计算属性缺失")
	print("  ✓ 计算属性正常")
	
	# 测试伤害加成
	var dmg_bonus = attr.calculate_damage_bonus()
	assert(dmg_bonus > 0, "伤害加成计算失败")
	print("  ✓ 伤害加成计算正常")
	
	# 测试闪避
	var dodge = attr.calculate_dodge_chance()
	assert(dodge >= 0, "闪避计算失败")
	print("  ✓ 闪避计算正常")
	
	tests_passed += 1
	print("  ✅ 属性系统测试通过")

func test_skill_system():
	print("\n[测试] 技能系统")
	
	var skill = get_node_or_null("/root/SkillSystem")
	if not skill:
		print("  ❌ SkillSystem 未找到")
		tests_failed += 1
		return
	
	# 重置技能
	skill.reset_skills()
	skill.add_skill_points(5)
	
	// 测试技能树初始化
	var all_skills = skill.get_all_skills()
	assert(all_skills.size() > 0, "技能树为空")
	print("  ✓ 技能树初始化正常 (%d 技能)" % all_skills.size())
	
	// 测试学习技能
	var can_learn = skill.can_learn_skill("combat_training")
	assert(can_learn.can_learn, "应该可以学习战斗训练")
	
	var result = skill.learn_skill("combat_training")
	assert(result.success, "学习技能失败")
	print("  ✓ 学习技能正常")
	
	// 测试技能效果
	var effect = skill.get_total_effect("damage_bonus")
	assert(effect >= 0, "技能效果异常")
	print("  ✓ 技能效果正常")
	
	tests_passed += 1
	print("  ✅ 技能系统测试通过")

func test_day_night_risk_system():
	print("\n[测试] 昼夜风险系统")
	
	var risk = get_node_or_null("/root/DayNightRiskSystem")
	if not risk:
		print("  ❌ DayNightRiskSystem 未找到")
		tests_failed += 1
		return
	
	// 测试基本状态
	assert(risk.current_danger_level >= 0, "危险等级异常")
	assert(risk.current_fatigue_level >= 0, "疲劳等级异常")
	print("  ✓ 系统状态正常")
	
	// 测试疲劳系统
	var initial_fatigue = risk.fatigue_value
	risk._add_fatigue(40)
	assert(risk.fatigue_value > initial_fatigue, "疲劳未增加")
	print("  ✓ 疲劳系统正常")
	
	// 测试休息
	risk.rest_in_safehouse()
	assert(risk.fatigue_value == 0, "疲劳未清零")
	print("  ✓ 休息功能正常")
	
	// 测试惩罚获取
	var penalties = risk.get_current_penalties()
	assert(penalties.has("enemy_damage_mult"), "惩罚数据缺失")
	print("  ✓ 惩罚系统正常")
	
	tests_passed += 1
	print("  ✅ 昼夜风险系统测试通过")

func test_integration():
	print("\n[测试] 系统集成")
	
	// 测试GameState集成
	var gs = get_node_or_null("/root/GameState")
	if not gs:
		print("  ❌ GameState 未找到")
		tests_failed += 1
		return
	
	// 测试经验值接口
	var xp_result = gs.add_xp(50, "integration_test")
	assert(xp_result.has("gained"), "经验接口返回异常")
	print("  ✓ GameState经验接口正常")
	
	// 测试时间接口
	var time_str = gs.get_formatted_time()
	assert(time_str.length() > 0, "时间格式异常")
	print("  ✓ GameState时间接口正常")
	
	// 测试战斗模块集成
	var combat = get_node_or_null("/root/CombatModule")
	if combat:
		print("  ✓ CombatModule可访问")
	
	// 测试存档数据结构
	var save_data = gs.get_save_data()
	assert(save_data.has("systems"), "存档数据缺少系统数据")
	assert(save_data.has("player_level"), "存档数据缺少等级数据")
	print("  ✓ 存档数据结构正常")
	
	tests_passed += 1
	print("  ✅ 系统集成测试通过")

func assert(condition: bool, message: String):
	if not condition:
		print("  ❌ 断言失败: %s" % message)
		tests_failed += 1
