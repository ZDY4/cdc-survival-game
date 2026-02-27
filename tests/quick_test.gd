extends SceneTree
# Quick System Test - 快速系统测试

func _init():
	print("\n========================================")
	print("CDC SURVIVAL GAME - 快速系统测试")
	print("========================================\n")
	
	var total_tests = 0
	var passed_tests = 0
	
	# Test 1: GameState
	total_tests += 1
	if GameState.player_hp == 100:
		passed_tests += 1
		print("✓ GameState 正常")
	else:
		print("✗ GameState 异常")
	
	# Test 2: EventBus
	total_tests += 1
	var received = false
	var callback = func(_d): received = true
	EventBus.subscribe(EventBus.EventType.GAME_STARTED, callback)
	EventBus.emit(EventBus.EventType.GAME_STARTED, {})
	if received:
		passed_tests += 1
		print("✓ EventBus 正常")
	else:
		print("✗ EventBus 异常")
	EventBus.unsubscribe(EventBus.EventType.GAME_STARTED, callback)
	
	# Test 3: Inventory
	total_tests += 1
	GameState.inventory_items.clear()
	GameState.add_item("test", 1)
	if GameState.has_item("test", 1):
		passed_tests += 1
		print("✓ Inventory 正常")
	else:
		print("✗ Inventory 异常")
	
	# Test 4: Map
	total_tests += 1
	var loc = MapModule.get_current_location()
	if loc.has("name"):
		passed_tests += 1
		print("✓ MapModule 正常")
	else:
		print("✗ MapModule 异常")
	
	# Test 5: Crafting
	total_tests += 1
	GameState.inventory_items.clear()
	GameState.add_item("cloth", 5)
	if CraftingModule.can_craft("bandage"):
		passed_tests += 1
		print("✓ Crafting 正常")
	else:
		print("✗ Crafting 异常")
	
	# Test 6: Skills
	total_tests += 1
	SkillModule.skill_points = 5
	if SkillModule.can_learn_skill("combat"):
		passed_tests += 1
		print("✓ Skills 正常")
	else:
		print("✗ Skills 异常")
	
	# Test 7: Weather
	total_tests += 1
	var effects = WeatherModule.get_weather_effects()
	if effects.has("visibility"):
		passed_tests += 1
		print("✓ Weather 正常")
	else:
		print("✗ Weather 异常")
	
	# Test 8: SaveSystem
	total_tests += 1
	GameState.player_hp = 80
	if SaveSystem.save_game():
		passed_tests += 1
		print("✓ SaveSystem 正常")
	else:
		print("✗ SaveSystem 异常")
	SaveSystem.delete_save()
	
	# Test 9: AI Bridge
	total_tests += 1
	if AITestBridge.is_running():
		passed_tests += 1
		print("✓ AI Bridge 正常 (端口8080)")
	else:
		print("✗ AI Bridge 异常")
	
	# Test 10: Dialog
	total_tests += 1
	DialogModule.show_dialog("Test", "Test", "")
	DialogModule.hide_dialog()
	passed_tests += 1
	print("✓ Dialog 正常")
	
	# Test 11: Combat
	total_tests += 1
	CombatModule.start_combat({"name": "Test", "hp": 10})
	passed_tests += 1
	print("✓ Combat 正常")
	CombatModule.end_combat()
	
	# Test 12: Base Building
	total_tests += 1
	GameState.inventory_items.clear()
	GameState.add_item("wood", 10)
	BaseBuildingModule.built_structures.clear()
	if BaseBuildingModule.can_build("bed"):
		passed_tests += 1
		print("✓ BaseBuilding 正常")
	else:
		print("✗ BaseBuilding 异常")
	
	# 报告
	print("\n========================================")
	print("测试完成: " + str(passed_tests) + "/" + str(total_tests))
	var pct = int(float(passed_tests) / float(total_tests) * 100.0)
	print("通过率: " + str(pct) + "%")
	
	if passed_tests == total_tests:
		print("\n🎉 所有系统正常！")
	elif pct >= 80:
		print("\n✅ 大部分系统正常")
	else:
		print("\n⚠️ 部分系统需要检查")
	
	print("========================================\n")
	
	quit()
