@tool
extends EditorScript
## 数据迁移工具
## 用于将GDScript中的硬编码数据提取到JSON文件
## 使用方法：在Godot编辑器中，点击 工具 -> 运行脚本 -> 选择此文件

const OUTPUT_DIR = "res://data/json/"

func _run():
	print("=== 数据迁移工具 ===")
	print("此工具帮助将GDScript中的硬编码数据迁移到JSON文件")
	print("")
	
	# 确保输出目录存在
	var dir = DirAccess.open("res://data/")
	if not dir:
		DirAccess.make_dir_recursive_absolute("res://data/json/")
		print("✓ 创建目录: res://data/json/")
	
	print("\n已创建的数据文件:")
	print("  - clues.json")
	print("  - story_chapters.json")
	print("  - recipes.json")
	print("  - enemies.json")
	print("  - quests.json")
	print("")
	print("待迁移的数据:")
	print("  ☐ equipment_system.gd - EQUIPMENT/ITEMS")
	print("  ☐ weapon_system.gd - WEAPONS")
	print("  ☐ map_module.gd - LOCATION_CONNECTIONS, LOCATION_DISTANCES")
	print("  ☐ encounter_database.gd - ENCOUNTER_DATA")
	print("")
	print("迁移步骤:")
	print("1. 从GDScript文件中复制数据字典")
	print("2. 使用在线工具或脚本将GDScript字典转换为JSON")
	print("3. 保存到 data/json/ 目录")
	print("4. 更新原系统文件，使用 DataManager 获取数据")
	print("")
	print("GDScript 到 JSON 转换注意事项:")
	print("- true/false 保持小写")
	print("- 字符串使用双引号")
	print("- 移除尾随逗号")
	print("- 注释需要删除或移动到单独文件")

## 辅助函数：将GDScript字典字符串转换为JSON
func convert_gdscript_dict_to_json(gdscript_text: String) -> String:
	var json_text = gdscript_text
	
	# 替换单引号为双引号
	json_text = json_text.replace("'", "\"")
	
	# 移除尾随逗号
	json_text = json_text.replace(",\n}", "\n}")
	json_text = json_text.replace(",\n]", "\n]")
	
	# 确保true/false是小写
	json_text = json_text.replace(": True", ": true")
	json_text = json_text.replace(": False", ": false")
	
	return json_text

## 验证JSON文件
func validate_json_file(path: String) -> bool:
	if not FileAccess.file_exists(path):
		push_error("文件不存在: " + path)
		return false
	
	var file = FileAccess.open(path, FileAccess.READ)
	var content = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var error = json.parse(content)
	
	if error != OK:
		push_error("JSON解析错误在 %s: %s" % [path, json.get_error_message()])
		return false
	
	print("✓ 验证通过: %s" % path)
	return true

## 批量验证所有JSON文件
func validate_all_json_files():
	print("\n=== 验证所有JSON文件 ===")
	var files = [
		"clues.json",
		"story_chapters.json",
		"recipes.json",
		"enemies.json",
		"quests.json"
	]
	
	var all_valid = true
	for file in files:
		var path = OUTPUT_DIR + file
		if not validate_json_file(path):
			all_valid = false
	
	if all_valid:
		print("\n✓ 所有文件验证通过!")
	else:
		print("\n✗ 某些文件验证失败")
