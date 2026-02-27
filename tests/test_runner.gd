extends SceneTree
# CarrySystemTestRunner - 测试运行器
# 可以直接在Godot中运行此脚本执行测试

func _initialize():
	print("=== 启动 CarrySystem 自动化测试 ===\n")
	
	# 加载测试脚本
	var test_script = load("res://tests/carry_system_test.gd")
	var test_instance = test_script.new()
	
	# 连接信号
	test_instance.test_completed.connect(_on_test_completed)
	
	# 运行测试
	var results = await test_instance.run_all_tests()
	
	# 根据结果退出
	if results.success:
		print("✅ 所有测试通过！")
		quit(0)
	else:
		print("❌ 有测试失败")
		quit(1)

func _on_test_completed():
	print("\n测试完成信号接收")
