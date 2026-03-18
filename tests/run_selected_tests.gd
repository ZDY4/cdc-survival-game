extends SceneTree

const TestRunnerScript = preload("res://tests/utils/test_runner.gd")

const DEFAULT_TEST_SCRIPTS: Array[String] = [
	"res://tests/functional/unit/test_turn_system.gd",
	"res://tests/functional/unit/test_player_controller.gd",
	"res://tests/functional/unit/test_interaction_attack_option.gd",
	"res://tests/functional/unit/test_debug_console.gd"
]

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var runner := TestRunnerScript.new()
	root.add_child(runner)

	var selected_scripts: Array[String] = DEFAULT_TEST_SCRIPTS.duplicate()
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.is_empty():
		selected_scripts.clear()
		for arg in args:
			selected_scripts.append(str(arg))

	for script_path in selected_scripts:
		var script: Script = load(script_path)
		assert(script != null, "Failed to load test script: %s" % script_path)
		assert(script.has_method("run_tests"), "Test script does not expose run_tests(): %s" % script_path)
		script.run_tests(runner)

	var passed: bool = await runner.run_layer(TestRunnerScript.TestLayer.FUNCTIONAL, true)
	for result_variant in runner._current_results:
		var result: TestRunnerScript.TestResult = result_variant
		var status := "PASS" if result.passed else "FAIL"
		var suffix := "" if result.error_message.is_empty() else " :: %s" % result.error_message
		print("[%s] %s%s" % [status, result.test_name, suffix])

	quit(0 if passed else 1)
