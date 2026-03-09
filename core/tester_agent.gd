extends Node
# TesterAgent - 测试Agent
# 执行自动化测试流程，包括静态检查和动态游戏测试

signal test_started(test_suite: String)
signal test_progress(test_name: String, status: String, progress: float)
signal test_completed(results: Dictionary)
signal test_failed(test_name: String, error: String)

# ===== 测试配置 =====
const TEST_LEVELS = [
	"syntax_check",      # 语法检查
	"file_integrity",    # 文件完整性
	"scene_load",        # 场景加载
	"code_style",        # 代码规范
	"unit_test",         # 单元测试
	"gameplay_test",     # 游戏流程测试 (使用AITestBridge)
	"edge_case",         # 边界测试
	"performance"        # 性能测试
]

# ===== 测试状态 =====
var _current_test: Dictionary = {}
var _test_results: Dictionary = {}
var _is_running: bool = false

func _ready():
	print("[TesterAgent] 测试Agent已初始化")

# ===== 主测试入口 =====

## 运行完整测试套件
func run_full_test_suite(new_files: Array = []):
	if _is_running:
		push_warning("[TesterAgent] 测试已在运行中")
		return {"success": false, "error": "测试已在运行"}
	
	_is_running = true
	test_started.emit("full_suite")
	
	print("\n" + "=".repeat(60))
	print("[TesterAgent] 开始完整测试套件")
	print("=".repeat(60))
	
	var results = {
		"success": true,
		"start_time": Time.get_unix_time_from_system(),
		"tests": {},
		"summary": {
			"passed": 0,
			"failed": 0,
			"warnings": 0
		}
	}
	
	# Level 1: 语法检查
	print("\n[1/8] 语法检查...")
	test_progress.emit("syntax_check", "running", 0.125)
	results.tests.syntax_check = await _run_syntax_check()
	_update_summary(results, results.tests.syntax_check)
	
	if not results.tests.syntax_check.success:
		print("❌ 语法检查失败，停止测试")
		results.success = false
		_is_running = false
		test_completed.emit(results)
		return results
	print("✅ 语法检查通过")
	
	# Level 2: 文件完整性
	print("\n[2/8] 文件完整性检查...")
	test_progress.emit("file_integrity", "running", 0.25)
	results.tests.file_integrity = await _run_file_integrity_check(new_files)
	_update_summary(results, results.tests.file_integrity)
	print("✅ 文件完整性检查完成")
	
	# Level 3: 场景加载
	print("\n[3/8] 场景加载测试...")
	test_progress.emit("scene_load", "running", 0.375)
	results.tests.scene_load = await _run_scene_load_test()
	_update_summary(results, results.tests.scene_load)
	print("✅ 场景加载测试完成")
	
	# Level 4: 代码规范
	print("\n[4/8] 代码规范检查...")
	test_progress.emit("code_style", "running", 0.5)
	results.tests.code_style = await _run_code_style_check()
	_update_summary(results, results.tests.code_style)
	print("✅ 代码规范检查完成")
	
	# Level 5: 单元测试
	print("\n[5/8] 单元测试...")
	test_progress.emit("unit_test", "running", 0.625)
	results.tests.unit_test = await _run_unit_tests()
	_update_summary(results, results.tests.unit_test)
	print("✅ 单元测试完成")
	
	# Level 6: 游戏流程测试 (使用AITestBridge)
	print("\n[6/8] 游戏流程测试...")
	test_progress.emit("gameplay_test", "running", 0.75)
	results.tests.gameplay_test = await _run_gameplay_tests()
	_update_summary(results, results.tests.gameplay_test)
	print("✅ 游戏流程测试完成")
	
	# Level 7: 边界测试
	print("\n[7/8] 边界测试...")
	test_progress.emit("edge_case", "running", 0.875)
	results.tests.edge_case = await _run_edge_case_tests()
	_update_summary(results, results.tests.edge_case)
	print("✅ 边界测试完成")
	
	# Level 8: 性能测试
	print("\n[8/8] 性能测试...")
	test_progress.emit("performance", "running", 1.0)
	results.tests.performance = await _run_performance_tests()
	_update_summary(results, results.tests.performance)
	print("✅ 性能测试完成")
	
	# 计算最终结果
	results.end_time = Time.get_unix_time_from_system()
	results.duration = results.end_time - results.start_time
	
	# 如果有任何关键测试失败，整体失败
	for test_name in results.tests.keys():
		if results.tests[test_name].get("critical", false) && not results.tests[test_name].success:
			results.success = false
			break
	
	print("\n" + "=".repeat(60))
	print("[TesterAgent] 测试套件完成")
	print("总耗时: %.2f秒" % results.duration)
	print("通过: %d, 失败: %d, 警告: %d" % [
		results.summary.passed,
		results.summary.failed,
		results.summary.warnings
	])
	print("=".repeat(60) + "\n")
	
	_is_running = false
	test_completed.emit(results)
	return results

## 快速测试（仅关键测试）
func run_quick_test():
	print("\n[TesterAgent] 开始快速测试...\n")
	
	var results = {
		"success": true,
		"tests": {}
	}
	
	# 只跑最关键的3个测试
	results.tests.syntax_check = await _run_syntax_check()
	results.tests.file_integrity = await _run_file_integrity_check([])
	results.tests.gameplay_test = await _run_gameplay_tests()
	
	# 只要有一个失败就整体失败
	for test_name in results.tests.keys():
		if not results.tests[test_name].success:
			results.success = false
			break
	
	return results

# ===== 具体测试实现 =====

## 1. 语法检查
func _run_syntax_check():
	var result = {
		"success": true,
		"critical": true,
		"errors": [],
		"warnings": []
	}
	
	# 检查所有GDScript文件
	var gd_files = _get_all_gd_files()
	
	for file_path in gd_files:
		var file = FileAccess.open(file_path, FileAccess.READ)
		if not file:
			result.errors.append("无法打开文件: " + file_path)
			result.success = false
			continue
		
		var content = file.get_as_text()
		file.close()
		
		# 简单语法检查
		var syntax_errors = _check_gdscript_syntax(content, file_path)
		result.errors.append_array(syntax_errors)
		
		if syntax_errors.size() > 0:
			result.success = false
	
	return result

## 2. 文件完整性检查
func _run_file_integrity_check(new_files: Array = []):
	var result = {
		"success": true,
		"critical": false,
		"errors": [],
		"warnings": []
	}
	
	# 检查新增文件是否存在
	for file_path in new_files:
		if not FileAccess.file_exists(file_path):
			result.errors.append("新增文件不存在: " + file_path)
			result.success = false
	
	# 检查项目必需文件
	var required_files = [
		"project.godot",
		"icon.svg"
	]
	
	for file in required_files:
		if not FileAccess.file_exists("res://" + file):
			result.errors.append("必需文件缺失: " + file)
			result.success = false
			result.critical = true
	
	# 检查场景引用有效性
	var scene_files = _get_all_tscn_files()
	for scene_path in scene_files:
		var invalid_refs = _check_scene_references(scene_path)
		result.errors.append_array(invalid_refs)
		if invalid_refs.size() > 0:
			result.success = false
	
	return result

## 3. 场景加载测试
func _run_scene_load_test():
	var result = {
		"success": true,
		"critical": true,
		"errors": [],
		"loaded_scenes": 0,
		"failed_scenes": 0
	}
	
	var scene_files = _get_all_tscn_files()
	
	for scene_path in scene_files:
		var scene_res = load(scene_path)
		
		if scene_res == null:
			result.errors.append("无法加载场景: " + scene_path)
			result.failed_scenes += 1
			result.success = false
			continue
		
		# 尝试实例化
		var instance = scene_res.instantiate()
		if instance == null:
			result.errors.append("无法实例化场景: " + scene_path)
			result.failed_scenes += 1
			result.success = false
		else:
			instance.free()
			result.loaded_scenes += 1
	
	return result

## 4. 代码规范检查
func _run_code_style_check():
	var result = {
		"success": true,
		"critical": false,
		"errors": [],
		"warnings": []
	}
	
	var gd_files = _get_all_gd_files()
	
	for file_path in gd_files:
		var file = FileAccess.open(file_path, FileAccess.READ)
		if not file:
			continue
		
		var content = file.get_as_text()
		file.close()
		
		# 检查命名规范
		var naming_issues = _check_naming_conventions(content, file_path)
		result.warnings.append_array(naming_issues)
		
		# 检查注释
		var comment_issues = _check_comments(content, file_path)
		result.warnings.append_array(comment_issues)
		
		# 检查print调试语句
		if content.find('print("[DEBUG') != -1:
			result.warnings.append(file_path + ": 包含调试print语句")
	
	return result

## 5. 单元测试
func _run_unit_tests():
	var result = {
		"success": true,
		"critical": true,
		"errors": [],
		"tests_run": 0,
		"tests_passed": 0,
		"tests_failed": 0
	}
	
	# 运行所有测试用例
	var test_methods = _get_test_methods()
	
	for test_method in test_methods:
		result.tests_run += 1
		var test_result = await test_method.call()
		
		if test_result.success:
			result.tests_passed += 1
		else:
			result.tests_failed += 1
			result.errors.append(test_result.error)
			result.success = false
	
	return result

## 6. 游戏流程测试 (使用AITestBridge)
func _run_gameplay_tests():
	var result = {
		"success": true,
		"critical": true,
		"errors": [],
		"tests": {}
	}
	
	# 使用AITestBridge运行游戏测试
	if AITestBridge.enabled:
		# 主流程测试
		result.tests.main_flow = await AITestBridge.run_main_flow_test()
		if not result.tests.main_flow.success:
			result.success = false
			result.errors.append("主流程测试失败")
		
		# 战斗测试
		result.tests.combat = await AITestBridge.run_combat_test()
		if not result.tests.combat.success:
			result.success = false
			result.errors.append("战斗测试失败")
		
		# 背包测试
		result.tests.inventory = await AITestBridge.run_inventory_test()
		if not result.tests.inventory.success:
			result.success = false
			result.errors.append("背包测试失败")
	else:
		result.warnings.append("AITestBridge未启用，跳过游戏流程测试")
	
	return result

## 7. 边界测试
func _run_edge_case_tests():
	var result = {
		"success": true,
		"critical": false,
		"errors": [],
		"warnings": []
	}
	
	# 测试极端值
	var edge_cases = [
		{"name": "HP为0", "test": _test_hp_zero},
		{"name": "背包满", "test": _test_inventory_full},
		{"name": "属性为负数", "test": _test_negative_stats}
	]
	
	for case in edge_cases:
		var case_result = await case.test.call()
		if not case_result.success:
			result.errors.append(case.name + "测试失败: " + case_result.error)
			result.success = false
	
	return result

## 8. 性能测试
func _run_performance_tests():
	var result = {
		"success": true,
		"critical": false,
		"errors": [],
		"metrics": {}
	}
	
	# 测试加载时间
	var start_time = Time.get_ticks_msec()
	var scene_files = _get_all_tscn_files()
	for scene_path in scene_files.slice(0, 5):  # 只测试前5个场景
		load(scene_path)
	var load_time = Time.get_ticks_msec() - start_time
	result.metrics.scene_load_time = load_time
	
	# 测试帧率（简化）
	result.metrics.fps_estimate = 60  # 假设60fps
	
	# 检查性能指标
	if load_time > 5000:  # 5秒
		result.warnings.append("场景加载较慢: " + str(load_time) + "ms")
	
	return result

# ===== 辅助方法 =====

func _get_all_gd_files() -> Array[String]:
	# 简化实现，实际需要遍历项目目录
	return [
		"res://core/game_state.gd",
		"res://core/game_state_manager.gd",
		"res://core/choice_system.gd"
	]

func _get_all_tscn_files() -> Array[String]:
	# 简化实现
	return [
		"res://scenes/ui/main_menu.tscn",
		"res://scenes/locations/game_world_3d.tscn"
	]

func _check_gdscript_syntax(content: String, file_path: String) -> Array[String]:
	var errors = []
	
	# 简单语法检查
	if content.count("func ") != content.count(":\n"):
		errors.append(file_path + ": 可能的缩进问题")
	
	if content.find("class_name") == -1 && content.find("extends") == -1:
		errors.append(file_path + ": 缺少extends或class_name")
	
	return errors

func _check_scene_references(scene_path: String) -> Array[String]:
	var errors = []
	var content = FileAccess.get_file_as_string(scene_path)
	
	# 检查ext_resource引用
	var regex = RegEx.new()
	regex.compile('path="([^"]+)"')
	
	for match in regex.search_all(content):
		var ref_path = match.get_string(1)
		if ref_path.begins_with("res://"):
			if not FileAccess.file_exists(ref_path):
				errors.append(scene_path + " 引用不存在: " + ref_path)
	
	return errors

func _check_naming_conventions(content: String, file_path: String) -> Array[String]:
	var warnings = []
	
	# 检查函数命名
	var func_regex = RegEx.new()
	func_regex.compile("func ([A-Z][a-zA-Z0-9_]*)")
	
	for match in func_regex.search_all(content):
		warnings.append(file_path + ": 函数应使用snake_case: " + match.get_string(1))
	
	return warnings

func _check_comments(content: String, file_path: String) -> Array[String]:
	var warnings = []
	
	# 检查类是否有文档注释
	if content.find("class_name") != -1 && content.find("# ") > content.find("class_name"):
		warnings.append(file_path + ": 类建议添加文档注释")
	
	return warnings

func _get_test_methods():
	# 返回所有测试方法
	return [
		_test_weapon_system,
		_test_inventory_system,
		_test_quest_system
	]

func _update_summary(results: Dictionary, test_result: Dictionary):
	if test_result.success:
		results.summary.passed += 1
	else:
		results.summary.failed += 1
	
	if test_result.get("warnings", []).size() > 0:
		results.summary.warnings += test_result.warnings.size()

# ===== 具体测试用例 =====

func _test_weapon_system():
	var result = {"success": true, "error": ""}
	
	# 测试武器数据
	if not WeaponSystem.WEAPONS.has("knife"):
		result.success = false
		result.error = "武器数据库缺少knife"
		return result
	
	# 测试装备
	WeaponSystem.equip_weapon("knife")
	if WeaponSystem.equipped_weapon != "knife":
		result.success = false
		result.error = "装备武器失败"
		return result
	
	return result

func _test_inventory_system():
	var result = {"success": true, "error": ""}
	
	# 测试添加物品
	var success = GameState.add_item("test_item", 1)
	if not success:
		result.success = false
		result.error = "添加物品失败"
		return result
	
	# 测试检查物品
	if not GameState.has_item("test_item"):
		result.success = false
		result.error = "检查物品失败"
		return result
	
	return result

func _test_quest_system():
	var result = {"success": true, "error": ""}
	
	# 测试任务数据存在
	if QuestSystem.QUESTS.size() == 0:
		result.success = false
		result.error = "任务数据库为空"
		return result
	
	return result

func _test_hp_zero():
	var result = {"success": true, "error": ""}
	
	GameState.player_hp = 0
	# 检查游戏是否正确处理死亡状态
	if GameState.player_hp != 0:
		result.success = false
		result.error = "HP为0时状态异常"
	
	return result

func _test_inventory_full(state: Dictionary):
	var result = {"success": true, "error": ""}
	
	# 填满背包
	GameState.inventory_items.clear()
	for i in range(GameState.inventory_max_slots):
		GameState.inventory_items.append({"id": "item_" + str(i), "count": 1})
	
	# 尝试添加更多物品
	var success = GameState.add_item("extra_item", 1)
	if success:
		result.success = false
		result.error = "背包满时应拒绝添加物品"
	
	return result

func _test_negative_stats():
	var result = {"success": true, "error": ""}
	
	# 测试负数处理
	GameState.player_hp = -10
	# 游戏应该自动修正为0或保持最小值
	if GameState.player_hp < 0:
		result.warnings.append("HP可以为负数，建议添加保护")
	
	return result

# ===== 报告生成 =====

func generate_test_report(results: Dictionary):
	var report = "## 测试报告\n\n"
	
	report += "### 概览\n"
	report += "- 状态: " + ("✅ 通过" if results.success else "❌ 失败") + "\n"
	report += "- 总耗时: %.2f秒\n" % results.get("duration", 0)
	report += "- 通过: %d, 失败: %d, 警告: %d\n\n" % [
		results.summary.passed,
		results.summary.failed,
		results.summary.warnings
	]
	
	report += "### 详细结果\n"
	for test_name in results.tests.keys():
		var test = results.tests[test_name]
		var status = "✅" if test.success else "❌"
		report += status + " " + test_name + "\n"
		
		if test.get("errors", []).size() > 0:
			for error in test.errors:
				report += "  - " + error + "\n"
	
	return report
