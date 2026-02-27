extends Node
# CarrySystemUIAutoTest - UI自动化测试
# 使用截图验证UI显示

signal test_completed(results: Dictionary)

const SCREENSHOT_PATH = "user://test_screenshots/"

func run_ui_tests():
	print("=== CarrySystem UI自动化测试 ===\n")
	
	var results = {
		"success": true,
		"tests": {},
		"screenshots": []
	}
	
	# 确保截图目录存在
	var dir = DirAccess.open("user://")
	if not dir.dir_exists("test_screenshots"):
		dir.make_dir("test_screenshots")
	
	# 测试1: 截图主菜单
	await get_tree().create_timer(1.0).timeout
	var screenshot1 = await _take_screenshot("main_menu")
	results.screenshots.append(screenshot1)
	
	# 测试2: 进入游戏并截图背包界面
	# 这里需要模拟点击开始游戏
	print("请在Godot中手动打开背包界面，然后截图...")
	
	# 等待一段时间让用户操作
	await get_tree().create_timer(5.0).timeout
	
	results.test_completed = true
	test_completed.emit(results)
	return results

func _take_screenshot():
	var viewport = get_viewport()
	var img = viewport.get_texture().get_image()
	
	var filename = SCREENSHOT_PATH + name + "_" + _get_timestamp() + ".png"
	img.save_png(filename)
	
	print("  📸 截图已保存: " + filename)
	return filename

func _get_timestamp():
	var dt = Time.get_datetime_dict_from_system()
	return "%04d%02d%02d_%02d%02d%02d" % [dt.year, dt.month, dt.day, dt.hour, dt.minute, dt.second]

# 检查UI元素是否存在
func check_ui_element():
	# 简化实现，实际需要遍历场景树
	var root = get_tree().root
	return _find_node_recursive(root, element_name)

func _find_node_recursive():
	if node.name == name:
		return true
	for child in node.get_children():
		if _find_node_recursive(child, name):
			return true
	return false
