extends SceneTree

func _init():
	print("Checking syntax of plugin.gd...")
	var script = load("res://addons/cdc_game_editor/plugin.gd")
	if script:
		print("Syntax check passed: Script loaded successfully")
		var instance = script.new()
		print("Instance created successfully")
		instance.free()
	else:
		print("Syntax check failed: Could not load script")
	quit()
