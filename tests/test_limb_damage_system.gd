extends SceneTree
## 部位伤害系统测试 - CDC末日生存游戏
## 运行：godot --script tests/test_limb_damage_system.gd

# 测试状态
var tests_passed: int = 0
var tests_failed: int = 0
var limb_system: LimbDamageSystem = null

func _initialize():
	print("=" * 60)
	print("CDC末日生存 - 部位伤害系统测试")
	print("=" * 60)
	
	# 创建并初始化部位伤害系统
	limb_system = LimbDamageSystem.new()
	limb_system._initialize_limbs()
	
	# 运行所有测试
	_test_limb_data()
	_test_damage_calculation()
	_test_state_transitions()
	_test_healing()
	_test_effects()
	_test_save_load()
	_test_edge_cases()
	
	# 输出结果
	print("\n" + "=" * 60)
	print("测试结果汇总")
	print("=" * 60)
	print("通过: %d" % tests_passed)
	print("失败: %d" % tests_failed)
	print("总计: %d" % (tests_passed + tests_failed))
	print("=" * 60)
	
	if tests_failed == 0:
		print("✅ 所有测试通过！")
	else:
		print("❌ 有测试未通过")
	
	quit()

# ========== 测试用例 ==========

func _test_limb_data():
	print("\n📋 测试: 部位数据定义")
	
	# 测试部位枚举
	_assert_equal(LimbDamageSystem.LimbType.HEAD, 0, "HEAD enum value")
	_assert_equal(LimbDamageSystem.LimbType.TORSO, 1, "TORSO enum value")
	_assert_equal(LimbDamageSystem.LimbType.LEFT_ARM, 2, "LEFT_ARM enum value")
	_assert_equal(LimbDamageSystem.LimbType.RIGHT_ARM, 3, "RIGHT_ARM enum value")
	_assert_equal(LimbDamageSystem.LimbType.LEGS, 4, "LEGS enum value")
	
	# 测试部位基础数据
	var head_data = LimbDamageSystem.LIMB_DATA[LimbDamageSystem.LimbType.HEAD]
	_assert_equal(head_data.name, "头部", "头部名称")
	_assert_equal(head_data.max_hp, 30, "头部最大HP")
	_assert_equal(head_data.damage_mult, 1.5, "头部伤害倍率")
	
	var torso_data = LimbDamageSystem.LIMB_DATA[LimbDamageSystem.LimbType.TORSO]
	_assert_equal(torso_data.max_hp, 100, "躯干最大HP")
	_assert_equal(torso_data.damage_mult, 1.0, "躯干伤害倍率")
	
	print("  ✅ 部位数据测试完成")

func _test_damage_calculation():
	print("\n💥 测试: 伤害计算")
	
	# 测试基础伤害计算
	var result = limb_system.calculate_limb_damage(20, LimbDamageSystem.LimbType.TORSO, false)
	_assert_equal(result.damage, 20, "躯干100%伤害")
	_assert_equal(result.limb, LimbDamageSystem.LimbType.TORSO, "目标部位正确")
	
	# 测试头部150%伤害
	result = limb_system.calculate_limb_damage(20, LimbDamageSystem.LimbType.HEAD, false)
	_assert_equal(result.damage, 30, "头部150%伤害 (20 * 1.5 = 30)")
	
	# 测试手臂80%伤害
	result = limb_system.calculate_limb_damage(20, LimbDamageSystem.LimbType.LEFT_ARM, false)
	_assert_equal(result.damage, 16, "手臂80%伤害 (20 * 0.8 = 16)")
	
	# 测试腿部90%伤害
	result = limb_system.calculate_limb_damage(20, LimbDamageSystem.LimbType.LEGS, false)
	_assert_equal(result.damage, 18, "腿部90%伤害 (20 * 0.9 = 18)")
	
	print("  ✅ 伤害计算测试完成")

func _test_state_transitions():
	print("\n🔄 测试: 状态转换")
	
	# 重置玩家部位
	limb_system.fully_restore_limb(-1, true)
	
	# 测试正常 -> 受损 (HP <= 30%)
	var result = limb_system.calculate_limb_damage(25, LimbDamageSystem.LimbType.HEAD, true)
	# 头部30HP，受到25*1.5=37伤害，会到0，但首次测试时是满血
	# 重新计算: 需要造成约9点伤害 (30 * 0.3 = 9)
	limb_system.fully_restore_limb(LimbDamageSystem.LimbType.HEAD, true)
	result = limb_system.calculate_limb_damage(7, LimbDamageSystem.LimbType.HEAD, true)
	limb_system.apply_limb_damage(result, true)
	
	var head_state = limb_system.get_limb_state(LimbDamageSystem.LimbType.HEAD, true)
	_assert_equal(head_state.state, LimbDamageSystem.LimbState.DAMAGED, 
		"头部应该处于受损状态 (剩余HP: %d)" % head_state.hp)
	
	# 测试受损 -> 损坏
	limb_system.fully_restore_limb(-1, true)
	result = limb_system.calculate_limb_damage(25, LimbDamageSystem.LimbType.HEAD, true)
	limb_system.apply_limb_damage(result, true)
	
	head_state = limb_system.get_limb_state(LimbDamageSystem.LimbType.HEAD, true)
	_assert_equal(head_state.state, LimbDamageSystem.LimbState.BROKEN, 
		"头部应该处于损坏状态 (剩余HP: %d)" % head_state.hp)
	
	print("  ✅ 状态转换测试完成")

func _test_healing():
	print("\n💊 测试: 治疗功能")
	
	# 先造成伤害
	limb_system.fully_restore_limb(-1, true)
	var result = limb_system.calculate_limb_damage(20, LimbDamageSystem.LimbType.HEAD, true)
	limb_system.apply_limb_damage(result, true)
	
	var before_hp = limb_system.get_limb_state(LimbDamageSystem.LimbType.HEAD, true).hp
	
	# 治疗
	var healed = limb_system.heal_limb(LimbDamageSystem.LimbType.HEAD, 15, true)
	var after_hp = limb_system.get_limb_state(LimbDamageSystem.LimbType.HEAD, true).hp
	
	_assert_true(healed > 0, "治疗量应该大于0")
	_assert_equal(after_hp, before_hp + healed, "治疗后HP应该增加")
	
	# 测试满血治疗（应该返回0）
	limb_system.fully_restore_limb(LimbDamageSystem.LimbType.HEAD, true)
	healed = limb_system.heal_limb(LimbDamageSystem.LimbType.HEAD, 10, true)
	_assert_equal(healed, 0, "满血时治疗应该返回0")
	
	# 测试全体治疗
	limb_system.fully_restore_limb(-1, true)
	limb_system.apply_limb_damage(limb_system.calculate_limb_damage(10, LimbDamageSystem.LimbType.HEAD, true), true)
	limb_system.apply_limb_damage(limb_system.calculate_limb_damage(20, LimbDamageSystem.LimbType.TORSO, true), true)
	
	var total_healed = limb_system.heal_all_limbs(10, true)
	_assert_true(total_healed > 0, "全体治疗应该有效")
	
	print("  ✅ 治疗功能测试完成")

func _test_effects():
	print("\n✨ 测试: 效果应用")
	
	# 测试头部效果
	limb_system.fully_restore_limb(-1, true)
	limb_system.apply_limb_damage(
		limb_system.calculate_limb_damage(25, LimbDamageSystem.LimbType.HEAD, true), 
		true
	)
	
	var effect = limb_system.get_limb_current_effect(LimbDamageSystem.LimbType.HEAD, true)
	_assert_true(effect.contains("眩晕") or effect.contains("暴击"), 
		"头部损坏应该产生相应效果: %s" % effect)
	
	# 测试腿部效果
	limb_system.fully_restore_limb(-1, true)
	limb_system.apply_limb_damage(
		limb_system.calculate_limb_damage(30, LimbDamageSystem.LimbType.LEGS, true), 
		true
	)
	
	effect = limb_system.get_limb_current_effect(LimbDamageSystem.LimbType.LEGS, true)
	_assert_true(effect.contains("闪避") or effect.contains("移动"), 
		"腿部损坏应该产生相应效果: %s" % effect)
	
	print("  ✅ 效果应用测试完成")

func _test_save_load():
	print("\n💾 测试: 存档/读档")
	
	# 设置一些状态
	limb_system.fully_restore_limb(-1, true)
	limb_system.apply_limb_damage(
		limb_system.calculate_limb_damage(25, LimbDamageSystem.LimbType.HEAD, true), 
		true
	)
	limb_system.apply_limb_damage(
		limb_system.calculate_limb_damage(40, LimbDamageSystem.LimbType.TORSO, true), 
		true
	)
	
	# 获取存档数据
	var save_data = limb_system.get_save_data()
	_assert_true(save_data.has("player_limbs"), "存档数据应该包含player_limbs")
	_assert_true(save_data.has("enemy_limbs"), "存档数据应该包含enemy_limbs")
	
	# 保存当前状态
	var old_head_hp = limb_system.get_limb_state(LimbDamageSystem.LimbType.HEAD, true).hp
	var old_torso_hp = limb_system.get_limb_state(LimbDamageSystem.LimbType.TORSO, true).hp
	
	# 恢复满血
	limb_system.fully_restore_limb(-1, true)
	
	# 加载存档
	limb_system.load_save_data(save_data)
	
	# 验证状态恢复
	var loaded_head_hp = limb_system.get_limb_state(LimbDamageSystem.LimbType.HEAD, true).hp
	var loaded_torso_hp = limb_system.get_limb_state(LimbDamageSystem.LimbType.TORSO, true).hp
	
	_assert_equal(loaded_head_hp, old_head_hp, "读档后头部HP应该一致")
	_assert_equal(loaded_torso_hp, old_torso_hp, "读档后躯干HP应该一致")
	
	print("  ✅ 存档/读档测试完成")

func _test_edge_cases():
	print("\n🔍 测试: 边界情况")
	
	# 测试过量伤害
	limb_system.fully_restore_limb(LimbDamageSystem.LimbType.HEAD, true)
	var result = limb_system.calculate_limb_damage(100, LimbDamageSystem.LimbType.HEAD, true)
	limb_system.apply_limb_damage(result, true)
	
	var head_state = limb_system.get_limb_state(LimbDamageSystem.LimbType.HEAD, true)
	_assert_equal(head_state.hp, 0, "过量伤害后HP应该为0，不为负")
	_assert_equal(head_state.state, LimbDamageSystem.LimbState.BROKEN, "应该处于损坏状态")
	
	# 测试已损坏部位的伤害减免
	result = limb_system.calculate_limb_damage(20, LimbDamageSystem.LimbType.HEAD, true)
	# 已损坏部位应该受到50%伤害: 20 * 1.5 * 0.5 = 15
	_assert_equal(result.damage, 15, "已损坏部位应该受到50%伤害")
	
	# 测试无效部位
	var functional = limb_system.get_functional_limbs(true)
	# 此时头部已损坏，应该从列表中排除
	_assert_false(LimbDamageSystem.LimbType.HEAD in functional, 
		"已损坏的头部不应该在有效部位列表中")
	
	# 测试部位名称和描述
	var head_name = limb_system.get_limb_name(LimbDamageSystem.LimbType.HEAD)
	_assert_equal(head_name, "头部", "部位名称应该正确")
	
	var head_desc = limb_system.get_limb_description(LimbDamageSystem.LimbType.HEAD)
	_assert_true(head_desc.contains("头部"), "部位描述应该包含名称")
	_assert_true(head_desc.contains("150%"), "部位描述应该包含伤害倍率")
	
	print("  ✅ 边界情况测试完成")

# ========== 断言方法 ==========

func _assert_equal(actual, expected, message: String):
	if actual == expected:
		tests_passed += 1
		print("  ✓ %s" % message)
	else:
		tests_failed += 1
		print("  ✗ %s" % message)
		print("    期望: %s, 实际: %s" % [str(expected), str(actual)])

func _assert_true(condition: bool, message: String):
	if condition:
		tests_passed += 1
		print("  ✓ %s" % message)
	else:
		tests_failed += 1
		print("  ✗ %s" % message)

func _assert_false(condition: bool, message: String):
	_assert_true(not condition, message)
