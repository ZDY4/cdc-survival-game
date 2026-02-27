extends Node

func _ready():
	print("Taking screenshot...")
	await get_tree().create_timer(1.0).timeout
	
	# 获取视口
	var viewport = get_viewport()
	var image = viewport.get_texture().get_image()
	
	# 保存截图
	var path = "user://screenshot.png"
	image.save_png(path)
	print("Screenshot saved to: " + path)
	
	# 复制到工作目录
	var source_path = ProjectSettings.globalize_path(path)
	var dest_path = "C:/Users/zdy/.openclaw/workspace/godot_screenshot.png"
	
	var file = FileAccess.open(source_path, FileAccess.READ)
	if file:
		var buffer = file.get_buffer(file.get_length())
		file.close()
		
		var out_file = FileAccess.open(dest_path, FileAccess.WRITE)
		if out_file:
			out_file.store_buffer(buffer)
			out_file.close()
			print("Screenshot copied to: " + dest_path)
		else:
			print("Failed to open destination file")
	else:
		print("Failed to open source file")
	
	# 退出
	get_tree().quit()
