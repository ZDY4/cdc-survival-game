extends RefCounted


static func to_int(value: Variant, default_value: int = 0) -> int:
	if value == null:
		return default_value

	match typeof(value):
		TYPE_INT:
			return value
		TYPE_FLOAT:
			var numeric_value: float = value
			return floori(numeric_value) if numeric_value >= 0.0 else ceili(numeric_value)
		TYPE_BOOL:
			return 1 if value else 0
		TYPE_STRING, TYPE_STRING_NAME:
			var text_value: String = str(value).strip_edges()
			if text_value.is_empty():
				return default_value
			return text_value.to_int()
		_:
			var fallback_text: String = str(value).strip_edges()
			if fallback_text.is_empty():
				return default_value
			return fallback_text.to_int()
