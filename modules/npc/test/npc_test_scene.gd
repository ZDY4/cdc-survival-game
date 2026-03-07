extends Node2D
## NPC系统测试场景
## 用于测试NPC的各种功能

class_name NPCTestScene

const NPCBase = preload("res://modules/npc/npc_base.gd")

var test_npc: NPCBase = null

func _ready():
	print("=== NPC系统测试开始 ===")
	
	# 等待NPCModule初始化
	await get_tree().create_timer(1.0).timeout
	
	# 运行测试
	_test_npc_spawning()
	_test_npc_dialog()
	_test_npc_trade()
	_test_npc_recruitment()
	
	print("=== NPC系统测试完成 ===")

func _test_npc_spawning():
	print("\n[测试1] NPC生成")
	
	# 生成商人老王
	var npc = NPCModule.spawn_npc("trader_lao_wang", "safehouse")
	if npc:
		print("✓ 成功生成NPC: %s" % npc.npc_name)
		test_npc = npc
	else:
		print("✗ 生成NPC失败")
	
	# 测试重复生成（应该返回已存在的实例）
	var npc2 = NPCModule.spawn_npc("trader_lao_wang", "safehouse")
	if npc2 == npc:
		print("✓ 重复生成正确处理")
	
	# 测试查询
	var npcs_at_location = NPCModule.get_npcs_at_location("safehouse")
	print("✓ %s位置有%d个NPC" % ["safehouse", npcs_at_location.size()])

func _test_npc_dialog():
	print("\n[测试2] NPC对话")
	
	if not test_npc:
		print("✗ 没有测试NPC，跳过")
		return
	
	# 检查对话组件
	if test_npc.dialog_component:
		print("✓ 对话组件已初始化")
		
		# 检查对话树
		if not test_npc.dialog_component.dialog_tree.is_empty():
			print("✓ 对话树已加载")
		else:
			print("✗ 对话树为空")
	else:
		print("✗ 对话组件未找到")

func _test_npc_trade():
	print("\n[测试3] NPC交易")
	
	if not test_npc:
		print("✗ 没有测试NPC，跳过")
		return
	
	if test_npc.can_trade():
		print("✓ NPC可以交易")
		
		if test_npc.trade_component:
			print("✓ 交易组件已初始化")
			
			# 检查库存
			var inventory = test_npc.trade_component.get_npc_inventory()
			print("✓ NPC库存有%d种物品" % inventory.size())
		else:
			print("✗ 交易组件未找到")
	else:
		print("✗ NPC不能交易")

func _test_npc_recruitment():
	print("\n[测试4] NPC招募")
	
	if not test_npc:
		print("✗ 没有测试NPC，跳过")
		return
	
	if test_npc.can_be_recruited():
		print("✓ NPC可以被招募")
		
		# 检查招募条件
		var result = test_npc.check_recruitment_conditions()
		print("  招募检查结果:")
		print("    - 是否通过: %s" % ("是" if result.success else "否"))
		print("    - 通过项: %d" % result.passed.size())
		print("    - 失败项: %d" % result.failed.size())
		
		for failed in result.failed:
			print("      * %s" % failed)
	else:
		print("✗ NPC不能被招募")

func _test_npc_mood():
	print("\n[测试5] NPC情绪")
	
	if not test_npc:
		return
	
	var initial_friendliness = test_npc.npc_data.mood.friendliness
	print("初始友好度: %d" % initial_friendliness)
	
	# 改变情绪
	test_npc.change_mood("friendliness", 10)
	
	var new_friendliness = test_npc.npc_data.mood.friendliness
	print("改变后友好度: %d" % new_friendliness)
	
	if new_friendliness == initial_friendliness + 10:
		print("✓ 情绪改变成功")
	else:
		print("✗ 情绪改变失败")

func _input(event):
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_1:
				# 生成NPC
				NPCModule.spawn_npc("trader_lao_wang", "safehouse")
				print("按1: 生成商人老王")
			
			KEY_2:
				# 开始对话
				var dialog_result = await NPCModule.start_dialog("trader_lao_wang")
				if dialog_result:
					print("按2: 开始对话")
				else:
					print("按2: 无法开始对话（NPC不存在或不可交互）")
			
			KEY_3:
				# 开始交易
				var trade_result = await NPCModule.start_trade("trader_lao_wang")
				if trade_result:
					print("按3: 开始交易")
				else:
					print("按3: 无法开始交易")
			
			KEY_4:
				# 增加友好度
				var npc = NPCModule.get_npc("trader_lao_wang")
				if npc:
					npc.change_mood("friendliness", 5)
					print("按4: 增加5点友好度，当前: %d" % npc.npc_data.mood.friendliness)
			
			KEY_0:
				# 显示测试帮助
				print("""
=== NPC测试快捷键 ===
[1] - 生成商人老王
[2] - 开始对话
[3] - 开始交易
[4] - 增加友好度
[0] - 显示帮助
""")

func _exit_tree():
	# 清理测试NPC
	if test_npc:
		NPCModule.despawn_npc(test_npc.npc_id)
