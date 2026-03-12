extends Node
class_name TestRunner

enum TestLayer {
	SANITY,
	FUNCTIONAL,
	AGENT
}

enum TestPriority {
	P0_CRITICAL,
	P1_MAJOR,
	P2_MINOR,
	P3_OPTIONAL
}

class TestResult:
	var test_name: String
	var layer: int
	var priority: int
	var passed: bool
	var duration: float
	var error_message: String

	func _init(name: String, test_layer: int, test_priority: int) -> void:
		test_name = name
		layer = test_layer
		priority = test_priority
		passed = false
		duration = 0.0
		error_message = ""

signal test_started(test_name: String, layer: int)
signal test_completed(result: TestResult)
signal layer_completed(layer: int, results: Array)
signal all_tests_completed(report: Dictionary)

var _tests: Array[Dictionary] = []
var _current_results: Array[TestResult] = []

func register_test(
	test_name: String,
	test_layer: int,
	test_priority: int,
	test_callable: Callable,
	setup: Callable = Callable(),
	teardown: Callable = Callable()
) -> void:
	_tests.append({
		"name": test_name,
		"layer": test_layer,
		"priority": test_priority,
		"callable": test_callable,
		"setup": setup,
		"teardown": teardown
	})

func run_layer(layer: int, stop_on_failure: bool = false) -> bool:
	_current_results.clear()
	var layer_tests: Array[Dictionary] = _get_tests_for_layer(layer)
	var passed := true

	for test_info in layer_tests:
		var result: TestResult = await _run_single_test(test_info)
		_current_results.append(result)
		if not result.passed:
			passed = false
			if stop_on_failure:
				break

	layer_completed.emit(layer, _current_results)
	return passed

func run_all_tests(stop_on_failure: bool = false) -> Dictionary:
	var report := {
		"timestamp": Time.get_unix_time_from_system(),
		"summary": {"total": 0, "passed": 0, "failed": 0},
		"layers": []
	}

	var sanity_passed: bool = await run_layer(TestLayer.SANITY, true)
	report.layers.append({
		"layer": "sanity",
		"status": "passed" if sanity_passed else "failed",
		"results": _current_results.duplicate()
	})

	if sanity_passed:
		var functional_passed: bool = await run_layer(TestLayer.FUNCTIONAL, stop_on_failure)
		report.layers.append({
			"layer": "functional",
			"status": "passed" if functional_passed else "failed",
			"results": _current_results.duplicate()
		})

	for layer_result in report.layers:
		var results: Array = layer_result.get("results", [])
		for result_variant in results:
			var result: TestResult = result_variant
			report.summary.total += 1
			if result.passed:
				report.summary.passed += 1
			else:
				report.summary.failed += 1

	all_tests_completed.emit(report)
	return report

func _get_tests_for_layer(layer: int) -> Array[Dictionary]:
	var filtered: Array[Dictionary] = []
	for test_info in _tests:
		if int(test_info.get("layer", -1)) == layer:
			filtered.append(test_info)
	filtered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("priority", 99)) < int(b.get("priority", 99))
	)
	return filtered

func _run_single_test(test_info: Dictionary) -> TestResult:
	var result := TestResult.new(
		str(test_info.get("name", "unknown")),
		int(test_info.get("layer", -1)),
		int(test_info.get("priority", TestPriority.P3_OPTIONAL))
	)
	test_started.emit(result.test_name, result.layer)

	var start_at: float = Time.get_unix_time_from_system()
	var setup_callable: Callable = test_info.get("setup", Callable())
	var test_callable: Callable = test_info.get("callable", Callable())
	var teardown_callable: Callable = test_info.get("teardown", Callable())

	if setup_callable.is_valid():
		await _call_and_await(setup_callable)

	if test_callable.is_valid():
		await _call_and_await(test_callable)
		result.passed = true
	else:
		result.passed = false
		result.error_message = "Invalid test callable"

	if teardown_callable.is_valid():
		await _call_and_await(teardown_callable)

	result.duration = Time.get_unix_time_from_system() - start_at
	test_completed.emit(result)
	return result

func _call_and_await(callable_ref: Callable) -> void:
	var call_result: Variant = callable_ref.call()
	if call_result is GDScriptFunctionState:
		await call_result
