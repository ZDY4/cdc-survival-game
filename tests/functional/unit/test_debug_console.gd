extends Node
class_name FunctionalTest_DebugConsole

class DebugConsoleTestHelper extends RefCounted:
	func return_one() -> int:
		return 1

	func return_two() -> int:
		return 2

	func build_panel() -> Control:
		return Control.new()

static func run_tests(runner: TestRunner) -> void:
	runner.register_test(
		"debug_console_autocomplete_suggests_commands_and_context_args",
		TestRunner.TestLayer.FUNCTIONAL,
		TestRunner.TestPriority.P1_MAJOR,
		_test_autocomplete_candidates
	)
	runner.register_test(
		"debug_console_autocomplete_panel_expands_above_input",
		TestRunner.TestLayer.FUNCTIONAL,
		TestRunner.TestPriority.P1_MAJOR,
		_test_autocomplete_panel_expands_above_input
	)
	runner.register_test(
		"debug_console_autocomplete_tab_and_navigation_work_with_history",
		TestRunner.TestLayer.FUNCTIONAL,
		TestRunner.TestPriority.P1_MAJOR,
		_test_autocomplete_keyboard_behavior
	)
	runner.register_test(
		"debug_console_autocomplete_clears_when_console_closes",
		TestRunner.TestLayer.FUNCTIONAL,
		TestRunner.TestPriority.P1_MAJOR,
		_test_autocomplete_clears_on_close
	)
	runner.register_test(
		"debug_console_toggle_key_closes_console_while_input_has_focus",
		TestRunner.TestLayer.FUNCTIONAL,
		TestRunner.TestPriority.P1_MAJOR,
		_test_toggle_key_closes_console_from_input
	)
	runner.register_test(
		"debug_console_hides_other_ui_while_visible",
		TestRunner.TestLayer.FUNCTIONAL,
		TestRunner.TestPriority.P1_MAJOR,
		_test_console_hides_other_ui
	)

static func _test_autocomplete_candidates() -> void:
	var debug_module := _get_debug_module()
	assert(debug_module != null, "DebugModule autoload should exist")
	await _prepare_console(debug_module)
	var helper := DebugConsoleTestHelper.new()

	debug_module.register_variable(
		"test_debug",
		"test_debug_var",
		Callable(helper, "return_one"),
		Callable(),
		"Temporary test variable"
	)
	debug_module.register_panel(
		"test_debug",
		"test_debug_panel",
		Callable(helper, "build_panel"),
		"Temporary test panel"
	)

	debug_module._input_line.text = "he"
	debug_module._input_line.caret_column = debug_module._input_line.text.length()
	debug_module._update_autocomplete()
	assert(_candidate_texts(debug_module).has("help"), "Typing 'he' should suggest 'help'")

	debug_module._input_line.text = "get "
	debug_module._input_line.caret_column = debug_module._input_line.text.length()
	debug_module._update_autocomplete()
	assert(
		_candidate_texts(debug_module).has("test_debug_var"),
		"'get ' should suggest registered variables"
	)

	debug_module._input_line.text = "panel o"
	debug_module._input_line.caret_column = debug_module._input_line.text.length()
	debug_module._update_autocomplete()
	assert(_candidate_texts(debug_module).has("open"), "'panel o' should suggest 'open'")

	debug_module._input_line.text = "panel open "
	debug_module._input_line.caret_column = debug_module._input_line.text.length()
	debug_module._update_autocomplete()
	assert(
		_candidate_texts(debug_module).has("test_debug_panel"),
		"'panel open ' should suggest registered panels"
	)

	debug_module.unregister_panel("test_debug_panel")
	debug_module.unregister_variable("test_debug_var")
	debug_module.unregister_module("test_debug")
	_reset_console(debug_module)

static func _test_autocomplete_panel_expands_above_input() -> void:
	var debug_module := _get_debug_module()
	assert(debug_module != null, "DebugModule autoload should exist")
	await _prepare_console(debug_module)

	debug_module._input_line.text = "he"
	debug_module._input_line.caret_column = debug_module._input_line.text.length()
	debug_module._update_autocomplete()

	assert(debug_module._autocomplete_panel.visible, "Autocomplete panel should be visible when candidates exist")
	assert(
		debug_module._autocomplete_panel.get_global_rect().position.y
		< debug_module._input_line.get_global_rect().position.y,
		"Autocomplete panel should expand upward and stay above the input line"
	)

	_reset_console(debug_module)

static func _test_autocomplete_keyboard_behavior() -> void:
	var debug_module := _get_debug_module()
	assert(debug_module != null, "DebugModule autoload should exist")
	await _prepare_console(debug_module)
	var helper := DebugConsoleTestHelper.new()

	debug_module.register_variable(
		"test_debug",
		"alpha_var",
		Callable(helper, "return_one"),
		Callable(),
		"Alpha variable"
	)
	debug_module.register_variable(
		"test_debug",
		"beta_var",
		Callable(helper, "return_two"),
		Callable(),
		"Beta variable"
	)

	debug_module._input_line.text = "he"
	debug_module._input_line.caret_column = debug_module._input_line.text.length()
	debug_module._update_autocomplete()
	debug_module._on_input_line_gui_input(_build_key_event(KEY_TAB))
	assert(debug_module._input_line.text == "help", "Tab should apply the highlighted command candidate")

	debug_module._input_line.text = "get "
	debug_module._input_line.caret_column = debug_module._input_line.text.length()
	debug_module._update_autocomplete()
	assert(debug_module._autocomplete_selection == 0, "Autocomplete should highlight the first item by default")
	debug_module._on_input_line_gui_input(_build_key_event(KEY_UP))
	assert(
		debug_module._autocomplete_selection == debug_module._autocomplete_candidates.size() - 1,
		"Up should wrap to the last autocomplete item when moving past the first item"
	)
	debug_module._on_input_line_gui_input(_build_key_event(KEY_DOWN))
	assert(debug_module._autocomplete_selection == 0, "Down should wrap back to the first item after the last item")
	debug_module._on_input_line_gui_input(_build_key_event(KEY_DOWN))
	assert(debug_module._autocomplete_selection == 1, "Down should move autocomplete selection")
	debug_module._on_input_line_gui_input(_build_key_event(KEY_UP))
	assert(debug_module._autocomplete_selection == 0, "Up should move autocomplete selection back")

	debug_module._command_history = ["clear", "modules"]
	debug_module._history_index = debug_module._command_history.size()
	debug_module._input_line.text = ""
	debug_module._input_line.caret_column = 0
	debug_module._clear_autocomplete()
	debug_module._on_input_line_gui_input(_build_key_event(KEY_UP))
	assert(debug_module._input_line.text == "modules", "Up should still navigate history when autocomplete is hidden")

	debug_module._input_line.text = "help"
	debug_module._input_line.caret_column = debug_module._input_line.text.length()
	debug_module._update_autocomplete()
	debug_module._on_command_submitted(debug_module._input_line.text)
	assert(
		debug_module._output_log.text.contains("Commands:"),
		"Enter submission should execute the command even if autocomplete was visible"
	)
	assert(not debug_module._autocomplete_panel.visible, "Submitting a command should hide autocomplete")

	debug_module.unregister_variable("alpha_var")
	debug_module.unregister_variable("beta_var")
	debug_module.unregister_module("test_debug")
	_reset_console(debug_module)

static func _test_autocomplete_clears_on_close() -> void:
	var debug_module := _get_debug_module()
	assert(debug_module != null, "DebugModule autoload should exist")
	await _prepare_console(debug_module)

	debug_module._input_line.text = "he"
	debug_module._input_line.caret_column = debug_module._input_line.text.length()
	debug_module._update_autocomplete()
	assert(not debug_module._autocomplete_candidates.is_empty(), "Autocomplete should be populated before closing")

	debug_module._set_console_visible(false)
	assert(debug_module._autocomplete_candidates.is_empty(), "Closing console should clear autocomplete candidates")
	assert(not debug_module._autocomplete_panel.visible, "Closing console should hide autocomplete panel")

static func _test_toggle_key_closes_console_from_input() -> void:
	var debug_module := _get_debug_module()
	assert(debug_module != null, "DebugModule autoload should exist")
	await _prepare_console(debug_module)

	assert(debug_module.is_console_visible(), "Console should start visible for the toggle-close test")
	debug_module._on_input_line_gui_input(_build_key_event(KEY_QUOTELEFT))
	assert(not debug_module.is_console_visible(), "Pressing the toggle key while the input has focus should close the console")

static func _test_console_hides_other_ui() -> void:
	var debug_module := _get_debug_module()
	assert(debug_module != null, "DebugModule autoload should exist")

	var loop := Engine.get_main_loop()
	assert(loop is SceneTree, "Main loop should be a SceneTree")
	var tree: SceneTree = loop
	assert(tree.root != null, "SceneTree root should exist")

	var visible_ui := Control.new()
	visible_ui.name = "VisibleTestUI"
	visible_ui.visible = true
	tree.root.add_child(visible_ui)

	var hidden_ui := CanvasLayer.new()
	hidden_ui.name = "HiddenTestUI"
	hidden_ui.visible = false
	tree.root.add_child(hidden_ui)
	await tree.process_frame

	await _prepare_console(debug_module)
	assert(not visible_ui.visible, "Showing the debug console should hide other visible UI")
	assert(not hidden_ui.visible, "UI that was already hidden should remain hidden while the console is open")
	assert(debug_module._console_panel.visible, "The debug console itself should remain visible")

	_reset_console(debug_module)
	assert(visible_ui.visible, "Closing the debug console should restore previously visible UI")
	assert(not hidden_ui.visible, "Closing the debug console should preserve UI that was hidden before opening")

	visible_ui.queue_free()
	hidden_ui.queue_free()
	await tree.process_frame

static func _get_debug_module() -> Node:
	var loop := Engine.get_main_loop()
	if not (loop is SceneTree):
		return null
	var tree: SceneTree = loop
	if tree.root == null:
		return null
	return tree.root.get_node_or_null("DebugModule")

static func _prepare_console(debug_module: Node) -> void:
	debug_module._set_console_visible(true)
	await Engine.get_main_loop().process_frame
	debug_module._log_lines.clear()
	debug_module._refresh_log_view()
	debug_module._command_history.clear()
	debug_module._history_index = -1
	debug_module._input_line.text = ""
	debug_module._input_line.caret_column = 0
	debug_module._clear_autocomplete()

static func _reset_console(debug_module: Node) -> void:
	debug_module._input_line.text = ""
	debug_module._input_line.caret_column = 0
	debug_module._clear_autocomplete()
	debug_module._set_console_visible(false)

static func _candidate_texts(debug_module: Node) -> Array[String]:
	var texts: Array[String] = []
	for candidate_variant in debug_module._autocomplete_candidates:
		var candidate: Dictionary = candidate_variant
		texts.append(str(candidate.get("text", "")))
	return texts

static func _build_key_event(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.pressed = true
	event.echo = false
	event.keycode = keycode
	event.physical_keycode = keycode
	return event
