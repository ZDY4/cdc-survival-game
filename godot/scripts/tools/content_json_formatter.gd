extends RefCounted


static func format_text(raw: String) -> String:
	var output := ""
	var depth := 0
	var in_string := false
	var escaped := false
	var pending_space := false
	for i in range(raw.length()):
		var ch := raw.substr(i, 1)
		if in_string:
			output += ch
			if escaped:
				escaped = false
			elif ch == "\\":
				escaped = true
			elif ch == "\"":
				in_string = false
			continue

		match ch:
			" ", "\t", "\n", "\r":
				continue
			"\"":
				if pending_space:
					output += " "
					pending_space = false
				output += ch
				in_string = true
			"{", "[":
				if pending_space:
					output += " "
					pending_space = false
				output += ch
				depth += 1
				output += "\n" + _indent(depth)
			"}", "]":
				pending_space = false
				depth -= 1
				if depth < 0:
					return ""
				output = output.rstrip(" \t\r\n")
				output += "\n" + _indent(depth) + ch
			",":
				pending_space = false
				output += ch + "\n" + _indent(depth)
			":":
				output = output.rstrip(" \t\r\n")
				output += ": "
				pending_space = false
			_:
				if pending_space:
					output += " "
					pending_space = false
				output += ch
				var next_index := i + 1
				if next_index < raw.length():
					var next := raw.substr(next_index, 1)
					if next in [" ", "\t", "\n", "\r"]:
						pending_space = true
	if in_string or depth != 0:
		return ""
	return output.rstrip(" \t\r\n") + "\n"


static func write_formatted_file(path: String) -> Dictionary:
	var before := FileAccess.get_file_as_string(path)
	var formatted := format_text(before)
	if formatted.is_empty():
		return _failed("format_failed", "failed to format JSON text: %s" % path)

	var changed := before != formatted
	if changed:
		# 内容格式化是 agent 复核入口，写入失败必须带路径，方便直接定位坏文件。
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			return _failed("write_failed", "failed to open for write: %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		file.store_string(formatted)

	return {
		"ok": true,
		"status": "ok",
		"changed": changed,
	}


static func _indent(depth: int) -> String:
	return "  ".repeat(max(0, depth))


static func _failed(code: String, message: String) -> Dictionary:
	return {
		"ok": false,
		"status": "failed",
		"code": code,
		"message": message,
	}
