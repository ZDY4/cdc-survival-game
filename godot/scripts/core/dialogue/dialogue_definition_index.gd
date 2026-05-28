extends RefCounted


func dialogue_data(dialogue_id: String, dialogue_library: Dictionary) -> Dictionary:
	var record: Dictionary = _dictionary_or_empty(dialogue_library.get(dialogue_id, {}))
	return _dictionary_or_empty(record.get("data", record))


func nodes_by_id(nodes: Array) -> Dictionary:
	var output: Dictionary = {}
	for node in nodes:
		var node_data: Dictionary = _dictionary_or_empty(node)
		var node_id: String = str(node_data.get("id", ""))
		if not node_id.is_empty():
			output[node_id] = node_data
	return output


func start_node(nodes: Array) -> Dictionary:
	for node in nodes:
		var node_data: Dictionary = _dictionary_or_empty(node)
		if bool(node_data.get("is_start", false)):
			return node_data
	if not nodes.is_empty():
		return _dictionary_or_empty(nodes[0])
	return {}


func resolve_option(choice_node: Dictionary, option_ref: Variant) -> Dictionary:
	var options: Array = _array_or_empty(choice_node.get("options", []))
	if options.is_empty():
		return {}
	if typeof(option_ref) == TYPE_INT:
		var index: int = int(option_ref)
		if index >= 0 and index < options.size():
			return _dictionary_or_empty(options[index])
		if index > 0 and index <= options.size():
			return _dictionary_or_empty(options[index - 1])
	var option_key: String = str(option_ref).strip_edges()
	if option_key.is_empty():
		return _dictionary_or_empty(options[0])
	if option_key.begins_with("choice_"):
		var choice_index: int = int(option_key.trim_prefix("choice_")) - 1
		if choice_index >= 0 and choice_index < options.size():
			return _dictionary_or_empty(options[choice_index])
	if option_key.is_valid_int():
		var parsed: int = int(option_key)
		if parsed > 0 and parsed <= options.size():
			return _dictionary_or_empty(options[parsed - 1])
		if parsed == 0:
			return _dictionary_or_empty(options[0])
	for option in options:
		var option_data: Dictionary = _dictionary_or_empty(option)
		if str(option_data.get("id", "")) == option_key:
			return option_data
		if str(option_data.get("next", "")) == option_key:
			return option_data
		if str(option_data.get("text", "")) == option_key:
			return option_data
	return {}


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
