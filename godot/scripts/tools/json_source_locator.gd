extends RefCounted


func locate(text: String, json_path: String) -> Dictionary:
	var tokens := _path_tokens(json_path)
	if tokens.is_empty() and json_path.strip_edges() != "$":
		return {}
	var index := _locate_value(text, _skip_whitespace(text, 0), tokens, 0)
	if index < 0:
		return {}
	var line_column := _line_column(text, index)
	return {
		"line": int(line_column.get("line", 0)),
		"column": int(line_column.get("column", 0)),
	}


func _locate_value(text: String, index: int, tokens: Array, token_index: int) -> int:
	index = _skip_whitespace(text, index)
	if token_index >= tokens.size():
		return index
	if index < 0 or index >= text.length():
		return -1
	var token: Variant = tokens[token_index]
	if typeof(token) == TYPE_STRING:
		return _locate_object_key(text, index, str(token), tokens, token_index)
	if typeof(token) == TYPE_INT:
		return _locate_array_index(text, index, int(token), tokens, token_index)
	return -1


func _locate_object_key(text: String, index: int, key: String, tokens: Array, token_index: int) -> int:
	if index >= text.length() or text[index] != "{":
		return -1
	index += 1
	while index < text.length():
		index = _skip_whitespace(text, index)
		if index >= text.length():
			return -1
		if text[index] == "}":
			return -1
		if text[index] != "\"":
			return -1
		var key_start := index
		var parsed_key := _parse_string(text, index)
		if not bool(parsed_key.get("ok", false)):
			return -1
		index = _skip_whitespace(text, int(parsed_key.get("end", -1)))
		if index >= text.length() or text[index] != ":":
			return -1
		var value_start := _skip_whitespace(text, index + 1)
		if str(parsed_key.get("value", "")) == key:
			if token_index == tokens.size() - 1:
				return key_start
			return _locate_value(text, value_start, tokens, token_index + 1)
		index = _skip_value(text, value_start)
		if index < 0:
			return -1
		index = _skip_whitespace(text, index)
		if index < text.length() and text[index] == ",":
			index += 1
			continue
		if index < text.length() and text[index] == "}":
			return -1
	return -1


func _locate_array_index(text: String, index: int, target_index: int, tokens: Array, token_index: int) -> int:
	if index >= text.length() or text[index] != "[":
		return -1
	index += 1
	var current := 0
	while index < text.length():
		index = _skip_whitespace(text, index)
		if index >= text.length():
			return -1
		if text[index] == "]":
			return -1
		if current == target_index:
			if token_index == tokens.size() - 1:
				return index
			return _locate_value(text, index, tokens, token_index + 1)
		index = _skip_value(text, index)
		if index < 0:
			return -1
		index = _skip_whitespace(text, index)
		if index < text.length() and text[index] == ",":
			index += 1
			current += 1
			continue
		if index < text.length() and text[index] == "]":
			return -1
	return -1


func _skip_value(text: String, index: int) -> int:
	index = _skip_whitespace(text, index)
	if index >= text.length():
		return -1
	var current := text[index]
	if current == "\"":
		var parsed := _parse_string(text, index)
		return int(parsed.get("end", -1)) if bool(parsed.get("ok", false)) else -1
	if current == "{":
		return _skip_composite(text, index, "{", "}")
	if current == "[":
		return _skip_composite(text, index, "[", "]")
	while index < text.length():
		current = text[index]
		if current == "," or current == "}" or current == "]" or _is_whitespace(current):
			return index
		index += 1
	return index


func _skip_composite(text: String, index: int, open_char: String, close_char: String) -> int:
	var depth := 0
	while index < text.length():
		var current := text[index]
		if current == "\"":
			var parsed := _parse_string(text, index)
			if not bool(parsed.get("ok", false)):
				return -1
			index = int(parsed.get("end", -1))
			continue
		if current == open_char:
			depth += 1
		elif current == close_char:
			depth -= 1
			if depth == 0:
				return index + 1
		index += 1
	return -1


func _parse_string(text: String, index: int) -> Dictionary:
	if index >= text.length() or text[index] != "\"":
		return {"ok": false}
	index += 1
	var value := ""
	while index < text.length():
		var current := text[index]
		if current == "\"":
			return {"ok": true, "value": value, "end": index + 1}
		if current == "\\":
			if index + 1 >= text.length():
				return {"ok": false}
			var escaped := text[index + 1]
			match escaped:
				"\"", "\\", "/":
					value += escaped
				"b":
					value += "\b"
				"f":
					value += "\f"
				"n":
					value += "\n"
				"r":
					value += "\r"
				"t":
					value += "\t"
				"u":
					value += "?"
					index += 4
				_:
					value += escaped
			index += 2
			continue
		value += current
		index += 1
	return {"ok": false}


func _path_tokens(json_path: String) -> Array:
	var path := json_path.strip_edges()
	if path == "$":
		return []
	if path.begins_with("$."):
		path = path.substr(2)
	elif path.begins_with("$"):
		path = path.substr(1)
	if path.begins_with("."):
		path = path.substr(1)
	var tokens: Array = []
	var part := ""
	var index := 0
	while index < path.length():
		var current := path[index]
		if current == ".":
			if not part.is_empty():
				tokens.append(part)
				part = ""
			index += 1
			continue
		if current == "[":
			if not part.is_empty():
				tokens.append(part)
				part = ""
			var end := path.find("]", index)
			if end < 0:
				return []
			var bracket := path.substr(index + 1, end - index - 1).strip_edges()
			if bracket.begins_with("\"") or bracket.begins_with("'"):
				var parsed := _parse_path_string(bracket, 0)
				if not bool(parsed.get("ok", false)) or int(parsed.get("end", -1)) != bracket.length():
					return []
				tokens.append(str(parsed.get("value", "")))
			else:
				if not bracket.is_valid_int():
					return []
				tokens.append(int(bracket))
			index = end + 1
			continue
		part += current
		index += 1
	if not part.is_empty():
		tokens.append(part)
	return tokens


func _parse_path_string(text: String, index: int) -> Dictionary:
	if index >= text.length() or (text[index] != "\"" and text[index] != "'"):
		return {"ok": false}
	var quote := text[index]
	index += 1
	var value := ""
	while index < text.length():
		var current := text[index]
		if current == quote:
			return {"ok": true, "value": value, "end": index + 1}
		if current == "\\":
			if index + 1 >= text.length():
				return {"ok": false}
			var escaped := text[index + 1]
			match escaped:
				"\"", "'", "\\", "/":
					value += escaped
				"b":
					value += "\b"
				"f":
					value += "\f"
				"n":
					value += "\n"
				"r":
					value += "\r"
				"t":
					value += "\t"
				_:
					value += escaped
			index += 2
			continue
		value += current
		index += 1
	return {"ok": false}


func _skip_whitespace(text: String, index: int) -> int:
	while index < text.length() and _is_whitespace(text[index]):
		index += 1
	return index


func _is_whitespace(value: String) -> bool:
	return value == " " or value == "\t" or value == "\n" or value == "\r"


func _line_column(text: String, index: int) -> Dictionary:
	var line := 1
	var column := 1
	var cursor := 0
	while cursor < index and cursor < text.length():
		if text[cursor] == "\n":
			line += 1
			column = 1
		else:
			column += 1
		cursor += 1
	return {"line": line, "column": column}
