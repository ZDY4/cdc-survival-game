extends RefCounted


func apply_operation(operation: Dictionary, selected_prompt: Dictionary, rebuild_command_result: Dictionary, rebuild_selected_prompt: Variant, rebuild_runtime_world: Callable, refresh_all_panels: Callable, refresh_operation_panels: Callable) -> Dictionary:
	var result: Dictionary = dictionary_or_empty(operation.get("result", {}))
	if bool(operation.get("rebuild_world", false)):
		var refresh_prompt: Dictionary = dictionary_or_empty(rebuild_selected_prompt) if typeof(rebuild_selected_prompt) == TYPE_DICTIONARY else selected_prompt
		if rebuild_runtime_world.is_valid():
			rebuild_runtime_world.call(refresh_prompt, rebuild_command_result)
	elif bool(operation.get("refresh_all_panels", false)):
		if refresh_all_panels.is_valid():
			refresh_all_panels.call(selected_prompt)
	else:
		if refresh_operation_panels.is_valid():
			refresh_operation_panels.call(array_or_empty(operation.get("refresh", [])), selected_prompt)
	return result


func dictionary_or_empty(value: Variant) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}


func array_or_empty(value: Variant) -> Array:
	return value if typeof(value) == TYPE_ARRAY else []
