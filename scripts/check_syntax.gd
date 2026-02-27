extends SceneTree

func _init():
	print("Checking GDScript files...")
	
	var files_to_check = [
		"res://core/tester_agent.gd",
		"res://modules/ai_test/ai_test_bridge.gd",
		"res://systems/combat_penalty_system.gd",
		"res://modules/combat/combat_module.gd"
	]
	
	for file_path in files_to_check:
		print("\nChecking: ", file_path)
		
		var error = check_script_syntax(file_path)
		if error:
			print("❌ ERROR: ", error)
		else:
			print("✅ OK")
	
	print("\n--- Check complete ---")
	quit()

func check_script_syntax(file_path: String) -> String:
	if not FileAccess.file_exists(file_path):
		return "File not found"
	
	var script = GDScript.new()
	var error = script.load(file_path)
	
	if error != OK:
		return "Load error"
	
	# Check compilation
	error = script.reload()
	if error != OK:
		return "Compile error"
	
	return ""
