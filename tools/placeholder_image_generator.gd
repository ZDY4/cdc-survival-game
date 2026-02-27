@tool
extends EditorScript
# PlaceholderImageGenerator - 生成占位符图片
# 在 Godot 编辑器中运行：File > Run > PlaceholderImageGenerator

const OUTPUT_DIR = "res://assets/placeholders"

const COLORS = {
	"player": Color(0.2, 0.4, 0.8),
	"zombie": Color(0.1, 0.5, 0.1),
	"npc": Color(0.9, 0.8, 0.2),
	"safehouse": Color(0.3, 0.25, 0.2),
	"street": Color(0.4, 0.4, 0.45),
	"street_a": Color(0.4, 0.4, 0.45),
	"street_b": Color(0.35, 0.35, 0.4),
	"door": Color(0.4, 0.3, 0.2),
	"locker": Color(0.5, 0.4, 0.3),
	"bed": Color(0.9, 0.9, 0.9),
	"chest": Color(0.8, 0.6, 0.2),
	"car": Color(0.5, 0.5, 0.55),
	"weapon": Color(0.6, 0.1, 0.1),
	"food": Color(0.9, 0.5, 0.2),
	"medicine": Color(0.2, 0.7, 0.4),
	"material": Color(0.5, 0.5, 0.5),
	"key": Color(1.0, 0.8, 0.0),
	"water": Color(0.2, 0.6, 1.0),
	"bandage": Color(1.0, 1.0, 1.0),
}

func _run():
	print("========================================")
	print("CDC Survival Game - 占位符图片生成器")
	print("========================================\n")
	
	# 创建目录
	_ensure_directories()
	
	var generated = 0
	
	# 生成角色
	print("[生成角色图片]")
	var characters = ["player", "zombie", "npc"]
	for char in characters:
		_create_character(char, Vector2i(32, 48))
		generated += 1
		print("  ✓ " + char + ".png")
	
	# 生成背景
	print("\n[生成背景图片]")
	var backgrounds = ["safehouse", "street", "street_a", "street_b"]
	for bg in backgrounds:
		_create_background(bg, Vector2i(640, 360))
		generated += 1
		print("  ✓ bg_" + bg + ".png")
	
	# 生成物体
	print("\n[生成物体图片]")
	var objects = ["door", "locker", "bed", "chest", "car"]
	for obj in objects:
		_create_object(obj, Vector2i(32, 32))
		generated += 1
		print("  ✓ " + obj + ".png")
	
	# 生成物品
	print("\n[生成物品图片]")
	var items = ["weapon", "food", "medicine", "key", "water", "bandage"]
	for item in items:
		_create_item(item, Vector2i(24, 24))
		generated += 1
		print("  ✓ item_" + item + ".png")
	
	# 生成特殊物品
	print("\n[生成特殊物品]")
	_create_item("medicine", Vector2i(24, 24), "first_aid_kit")
	_create_item("water", Vector2i(24, 24), "water_bottle")
	_create_item("food", Vector2i(24, 24), "food_canned")
	_create_item("weapon", Vector2i(24, 24), "knife")
	generated += 4
	print("  ✓ first_aid_kit.png")
	print("  ✓ water_bottle.png")
	print("  ✓ food_canned.png")
	print("  ✓ knife.png")
	
	print("\n========================================")
	print("总共生成: " + str(generated + 4) + " 张图片")
	print("输出目录: " + OUTPUT_DIR)
	print("========================================")

func _ensure_directories():
	var dir = DirAccess.open("res://")
	if not dir.dir_exists("assets"):
		dir.make_dir("assets")
	if not dir.dir_exists("assets/placeholders"):
		dir.make_dir("assets/placeholders")
	if not dir.dir_exists("assets/placeholders/characters"):
		dir.make_dir("assets/placeholders/characters")
	if not dir.dir_exists("assets/placeholders/backgrounds"):
		dir.make_dir("assets/placeholders/backgrounds")
	if not dir.dir_exists("assets/placeholders/objects"):
		dir.make_dir("assets/placeholders/objects")
	if not dir.dir_exists("assets/placeholders/items"):
		dir.make_dir("assets/placeholders/items")

func _create_character():
	var img = Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var color = COLORS.get(name, Color.GRAY)
	
	# 填充透明
	img.fill(Color(0, 0, 0, 0))
	
	# 身体
	for x in range(4, size.x - 4):
		for y in range(12, size.y - 4):
			img.set_pixel(x, y, color)
	
	# 头部
	var head_y = 4
	var head_radius = 6
	var center_x = size.x / 2
	for x in range(size.x):
		for y in range(head_y, head_y + head_radius * 2):
			var dist = Vector2(x, y).distance_to(Vector2(center_x, head_y + head_radius))
			if dist <= head_radius:
				img.set_pixel(x, y, color)
	
	# 眼睛
	var eye_color = name != "zombie" ? Color.WHITE : Color.RED
	img.set_pixel(center_x - 3, head_y + 6, eye_color)
	img.set_pixel(center_x - 2, head_y + 6, eye_color)
	img.set_pixel(center_x + 2, head_y + 6, eye_color)
	img.set_pixel(center_x + 3, head_y + 6, eye_color)
	
	# 保存
	img.save_png(OUTPUT_DIR + "/characters/" + name + ".png")

func _create_background():
	var img = Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var color = COLORS.get(name, Color.DARK_GRAY)
	
	# 填充背景色
	img.fill(color)
	
	# 添加噪点
	for i in range(0, size.x, 40):
		for j in range(0, size.y, 40):
			if (i + j) % 80 == 0:
				for x in range(i, min(i + 20, size.x)):
					for y in range(j, min(j + 20, size.y)):
						var c = img.get_pixel(x, y)
						img.set_pixel(x, y, c.lightened(0.1))
	
	# 添加文字标识
	# 注：Godot 4 的 Image 不直接支持文字渲染，这里用矩形代替
	for x in range(10, 100):
		for y in range(10, 30):
			img.set_pixel(x, y, Color(1, 1, 1, 0.8))
	
	img.save_png(OUTPUT_DIR + "/backgrounds/bg_" + name + ".png")

func _create_object():
	var img = Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var color = COLORS.get(name, Color.GRAY)
	
	# 透明背景
	img.fill(Color(0, 0, 0, 0))
	
	# 绘制矩形物体
	for x in range(2, size.x - 2):
		for y in range(2, size.y - 2):
			img.set_pixel(x, y, color)
	
	# 添加边框
	for x in range(size.x):
		img.set_pixel(x, 0, Color.BLACK)
		img.set_pixel(x, size.y - 1, Color.BLACK)
	for y in range(size.y):
		img.set_pixel(0, y, Color.BLACK)
		img.set_pixel(size.x - 1, y, Color.BLACK)
	
	# 中心点
	img.set_pixel(size.x / 2, size.y / 2, Color.WHITE)
	
	img.save_png(OUTPUT_DIR + "/objects/" + name + ".png")

func _create_item():
	if filename.is_empty():
		filename = "item_" + name
	
	var img = Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var color = COLORS.get(name, Color.GRAY)
	
	# 透明背景
	img.fill(Color(0, 0, 0, 0))
	
	# 绘制圆形
	var center = Vector2(size.x / 2, size.y / 2)
	var radius = size.x / 2 - 2
	
	for x in range(size.x):
		for y in range(size.y):
			var dist = Vector2(x, y).distance_to(center)
			if dist <= radius:
				img.set_pixel(x, y, color)
	
	img.save_png(OUTPUT_DIR + "/items/" + filename + ".png")
