# tests/utils/test_runner.gd
# 测试运行器 - 支持分层测试

class_name TestRunner
extends Node

enum TestLayer {
    SANITY,         # 冒烟测试
    FUNCTIONAL,     # 功能测试
    AGENT          # Agent测试
}

enum TestPriority {
    P0_CRITICAL,    # 核心功能，必须100%通过
    P1_MAJOR,       # 主要功能，>95%通过
    P2_MINOR,       # 次要功能，>80%通过
    P3_OPTIONAL     # 可选功能
}

# 测试结果
class TestResult:
    var test_name: String
    var layer: int
    var priority: int
    var passed: bool
    var duration: float
    var error_message: String = ""
    var stack_trace: String = ""
    
    func _init():
        test_name = name
        layer = test_layer
        priority = test_priority
        passed = false
        duration = 0.0

# 测试套件
class TestSuite:
    var name: String
    var layer: int
    var tests: Array[TestResult] = []
    var setup_func: Callable
    var teardown_func: Callable
    
    func _init():
        name = suite_name
        layer = test_layer

# 运行状态
var _current_layer: int = -1
var _suites: Array[TestSuite] = []
var _current_results: Array[TestResult] = []

signal test_started(test_name: String, layer: int)
signal test_completed(result: TestResult)
signal layer_completed(layer: int, results: Array[TestResult])
signal all_tests_completed(report: Dictionary)

# 运行指定层的测试
func run_layer():
    _current_layer = layer
    _current_results.clear()
    
    print_rich("[color=cyan]========================================[/color]")
    print_rich("[color=cyan]Running Test Layer: %s[/color]" % _layer_name(layer))
    print_rich("[color=cyan]========================================[/color]")
    
    var layer_passed = true
    var layer_tests = _get_tests_for_layer(layer)
    
    for test_info in layer_tests:
        var result = _run_single_test(test_info)
        _current_results.append(result)
        
        if not result.passed:
            layer_passed = false
            if stop_on_failure:
                break
    
    layer_completed.emit(layer, _current_results)
    _print_layer_summary(layer, _current_results)
    
    return layer_passed

# 运行所有测试
func run_all_tests():
    var start_time = Time.get_unix_time_from_system()
    var all_results: Array[TestResult] = []
    var final_report = {
        "timestamp": start_time,
        "layers": [],
        "summary": {
            "total": 0,
            "passed": 0,
            "failed": 0,
            "skipped": 0,
            "duration": 0.0
        }
    }
    
    # Layer 1: Sanity
    if not run_layer(TestLayer.SANITY, true):
        print_rich("[color=red]SANITY TESTS FAILED - Stopping[/color]")
        final_report.summary.duration = Time.get_unix_time_from_system() - start_time
        all_tests_completed.emit(final_report)
        return final_report
    
    final_report.layers.append({
        "layer": "sanity",
        "status": "passed",
        "results": _current_results.duplicate()
    })
    all_results.append_array(_current_results)
    
    # Layer 2: Functional
    if not run_layer(TestLayer.FUNCTIONAL, stop_on_failure):
        print_rich("[color=red]FUNCTIONAL TESTS FAILED[/color]")
    
    final_report.layers.append({
        "layer": "functional",
		"status": "passed" if _layer_passed(TestLayer.FUNCTIONAL) else "failed",
        "results": _current_results.duplicate()
    })
    all_results.append_array(_current_results)
    
    # Layer 3: Agent (only if functional passed)
    if _layer_passed(TestLayer.FUNCTIONAL):
        print_rich("[color=green]Functional tests passed - Agent tests can now run[/color]")
    else:
        print_rich("[color=yellow]Functional tests failed - Skipping Agent tests[/color]")
    
    # 生成汇总
    final_report.summary.duration = Time.get_unix_time_from_system() - start_time
    for result in all_results:
        final_report.summary.total += 1
        if result.passed:
            final_report.summary.passed += 1
        else:
            final_report.summary.failed += 1
    
    _print_final_report(final_report)
    all_tests_completed.emit(final_report)
    
    return final_report

# 运行单个测试
func _run_single_test():
    var result = TestResult.new(
        test_info.name,
        test_info.layer,
        test_info.priority
    )
    
    test_started.emit(test_info.name, test_info.layer)
    
    var start_time = Time.get_unix_time_from_system()
    
    # 执行测试
    if test_info.has("callable"):
        var test_callable: Callable = test_info.callable
        
        # Setup
        if test_info.has("setup"):
            test_info.setup.call()
        
        # Run test with error handling
        var error = _run_with_timeout(test_callable, result, test_info.get("timeout", 10.0))
        
        # Teardown
        if test_info.has("teardown"):
            test_info.teardown.call()
        
        if error.is_empty():
            result.passed = true
        else:
            result.error_message = error
    
    result.duration = Time.get_unix_time_from_system() - start_time
    
    test_completed.emit(result)
    _print_test_result(result)
    
    return result

# 带超时的测试执行
func _run_with_timeout():
    var error_msg = ""
    
    # 使用信号和计时器实现超时
    var completed = false
    var test_thread = Thread.new()
    
    var test_func = func():
        try:
            test_callable.call()
            completed = true
        except:
            error_msg = "Test threw exception: " + str(get_stack())
    
    test_thread.start(test_func)
    
    var start = Time.get_unix_time_from_system()
    while not completed && (Time.get_unix_time_from_system() - start) < timeout_sec:
        OS.delay_msec(10)
    
    if not completed:
        error_msg = "Test timeout after %f seconds" % timeout_sec
    
    return error_msg

# 注册测试
func register_test(test_name: String, test_layer: int, test_priority: int, 
                   test_callable: Callable, setup: Callable = Callable(), 
                   teardown: Callable = Callable()) :
    
    _suites.append({
        "name": test_name,
        "layer": test_layer,
        "priority": test_priority,
        "callable": test_callable,
        "setup": setup,
        "teardown": teardown
    })

# 获取指定层的测试
func _get_tests_for_layer():
    var tests = []
    for suite in _suites:
        if suite.layer == layer:
            tests.append(suite)
    
    # 按优先级排序 (P0优先)
    tests.sort_custom(func(a, b): return a.priority < b.priority)
    
    return tests

# 检查层是否通过
func _layer_passed():
    for result in _current_results:
        if result.layer == layer && not result.passed:
            # P0失败 = 层失败
            if result.priority == TestPriority.P0_CRITICAL:
                return false
    return true

# 获取层名称
func _layer_name():
    match layer:
        TestLayer.SANITY: return "SANITY"
        TestLayer.FUNCTIONAL: return "FUNCTIONAL"
        TestLayer.AGENT: return "AGENT"
        _: return "UNKNOWN"

# 打印测试结果
func _print_test_result(result: Dictionary):
    var status_color = "green" if result.passed else "red"
    var status_icon = "✓" if result.passed else "✗"
    var priority_str = _priority_name(result.priority)
    
    print_rich("[color=%s]%s [%s] %s (%.2fs)[/color]" % [
        status_color, status_icon, priority_str, result.test_name, result.duration
    ])
    
    if not result.passed && not result.error_message.is_empty():
        print_rich("[color=red]      Error: %s[/color]" % result.error_message)

# 打印层汇总
func _print_layer_summary():
    var passed = results.filter(func(r): return r.passed).size()
    var total = results.size()
    var duration = results.reduce(func(acc, r): return acc + r.duration, 0.0)
    
    var color: String
    if passed == total:
        color = "green"
    elif passed >= total * 0.8:
        color = "yellow"
    else:
        color = "red"
    
    print_rich("[color=%s]----------------------------------------[/color]" % color)
    print_rich("[color=%s]Layer Summary: %d/%d passed (%.2fs)[/color]" % [color, passed, total, duration])
    print_rich("[color=%s]----------------------------------------[/color]" % color)

# 打印最终报告
func _print_final_report():
    print_rich("[color=cyan]========================================[/color]")
    print_rich("[color=cyan]FINAL TEST REPORT[/color]")
    print_rich("[color=cyan]========================================[/color]")
    
    var summary = report.summary
    var color: String
    if summary.failed == 0:
        color = "green"
    elif summary.failed < summary.total * 0.2:
        color = "yellow"
    else:
        color = "red"
    
    print_rich("[color=%s]Total: %d | Passed: %d | Failed: %d | Duration: %.2fs[/color]" % [
        color, summary.total, summary.passed, summary.failed, summary.duration
    ])
    
    print_rich("[color=cyan]========================================[/color]")

# 获取优先级名称
func _priority_name(priority: TestPriority) -> String:
    match priority:
        TestPriority.P0_CRITICAL: return "P0"
        TestPriority.P1_MAJOR: return "P1"
        TestPriority.P2_MINOR: return "P2"
        TestPriority.P3_OPTIONAL: return "P3"
        _: return "??"
