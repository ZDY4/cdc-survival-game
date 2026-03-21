extends RefCounted
## GameplayTagQuery - Serializable expression tree for tag matching.

class_name GameplayTagQuery

const GameplayTagContainerScript = preload("res://addons/gameplay_tags/runtime/gameplay_tag_container.gd")

const EXPR_ANY_TAGS: String = "any_tags"
const EXPR_ALL_TAGS: String = "all_tags"
const EXPR_NO_TAGS: String = "no_tags"
const EXPR_ANY_EXPR: String = "any_expr"
const EXPR_ALL_EXPR: String = "all_expr"
const EXPR_NO_EXPR: String = "no_expr"

var _root_expression: Dictionary = {}

func _init(expression: Dictionary = {}) -> void:
	if expression.is_empty():
		_root_expression = {
			"type": EXPR_ALL_TAGS,
			"tags": [],
			"expressions": []
		}
	else:
		_root_expression = _sanitize_expression(expression)

static func any_tags_match(tags: Array[StringName]):
	return load("res://addons/gameplay_tags/runtime/gameplay_tag_query.gd").new({
		"type": EXPR_ANY_TAGS,
		"tags": _tags_to_serializable(tags),
		"expressions": []
	})

static func all_tags_match(tags: Array[StringName]):
	return load("res://addons/gameplay_tags/runtime/gameplay_tag_query.gd").new({
		"type": EXPR_ALL_TAGS,
		"tags": _tags_to_serializable(tags),
		"expressions": []
	})

static func no_tags_match(tags: Array[StringName]):
	return load("res://addons/gameplay_tags/runtime/gameplay_tag_query.gd").new({
		"type": EXPR_NO_TAGS,
		"tags": _tags_to_serializable(tags),
		"expressions": []
	})

static func any_expr_match(expressions: Array) -> Variant:
	return load("res://addons/gameplay_tags/runtime/gameplay_tag_query.gd").new({
		"type": EXPR_ANY_EXPR,
		"tags": [],
		"expressions": _expressions_to_serializable(expressions)
	})

static func all_expr_match(expressions: Array) -> Variant:
	return load("res://addons/gameplay_tags/runtime/gameplay_tag_query.gd").new({
		"type": EXPR_ALL_EXPR,
		"tags": [],
		"expressions": _expressions_to_serializable(expressions)
	})

static func no_expr_match(expressions: Array) -> Variant:
	return load("res://addons/gameplay_tags/runtime/gameplay_tag_query.gd").new({
		"type": EXPR_NO_EXPR,
		"tags": [],
		"expressions": _expressions_to_serializable(expressions)
	})

static func from_dict(data: Dictionary) -> Variant:
	return load("res://addons/gameplay_tags/runtime/gameplay_tag_query.gd").new(data)

func to_dict() -> Dictionary:
	return _root_expression.duplicate(true)

func evaluate(container) -> bool:
	if container == null:
		return false
	if not (container is GameplayTagContainerScript):
		return false
	return _evaluate_expression(_root_expression, container)

func _evaluate_expression(expression: Dictionary, container) -> bool:
	var expression_type: String = str(expression.get("type", EXPR_ALL_TAGS))
	var tags: Array[StringName] = _parse_tags(expression.get("tags", []))
	var sub_expressions: Array = expression.get("expressions", [])

	match expression_type:
		EXPR_ANY_TAGS:
			if tags.is_empty():
				return false
			return container.has_any(tags, false)
		EXPR_ALL_TAGS:
			if tags.is_empty():
				return true
			return container.has_all(tags, false)
		EXPR_NO_TAGS:
			if tags.is_empty():
				return true
			return not container.has_any(tags, false)
		EXPR_ANY_EXPR:
			for sub_expression in sub_expressions:
				if sub_expression is Dictionary and _evaluate_expression(sub_expression, container):
					return true
			return false
		EXPR_ALL_EXPR:
			for sub_expression in sub_expressions:
				if sub_expression is Dictionary and not _evaluate_expression(sub_expression, container):
					return false
			return true
		EXPR_NO_EXPR:
			for sub_expression in sub_expressions:
				if sub_expression is Dictionary and _evaluate_expression(sub_expression, container):
					return false
			return true
		_:
			return false

func _sanitize_expression(expression: Dictionary) -> Dictionary:
	var expression_type: String = str(expression.get("type", EXPR_ALL_TAGS))
	if not _is_supported_expression_type(expression_type):
		expression_type = EXPR_ALL_TAGS

	var cleaned_tags: Array[String] = []
	var raw_tags: Variant = expression.get("tags", [])
	if raw_tags is Array:
		for raw_tag in raw_tags:
			var normalized: String = _normalize_tag(raw_tag)
			if not normalized.is_empty():
				cleaned_tags.append(normalized)

	var cleaned_expressions: Array[Dictionary] = []
	var raw_expressions: Variant = expression.get("expressions", [])
	if raw_expressions is Array:
		for raw_expression in raw_expressions:
			if raw_expression is Dictionary:
				cleaned_expressions.append(_sanitize_expression(raw_expression))

	return {
		"type": expression_type,
		"tags": cleaned_tags,
		"expressions": cleaned_expressions
	}

func _parse_tags(raw_tags: Variant) -> Array[StringName]:
	var result: Array[StringName] = []
	if not (raw_tags is Array):
		return result
	for raw_tag in raw_tags:
		var normalized: String = _normalize_tag(raw_tag)
		if normalized.is_empty():
			continue
		result.append(StringName(normalized))
	return result

func _normalize_tag(raw_tag: Variant) -> String:
	var text: String = str(raw_tag).strip_edges()
	while text.contains(".."):
		text = text.replace("..", ".")
	if text.begins_with("."):
		text = text.substr(1)
	if text.ends_with(".") and text.length() > 0:
		text = text.substr(0, text.length() - 1)
	return text

func _is_supported_expression_type(expression_type: String) -> bool:
	return expression_type == EXPR_ANY_TAGS \
		or expression_type == EXPR_ALL_TAGS \
		or expression_type == EXPR_NO_TAGS \
		or expression_type == EXPR_ANY_EXPR \
		or expression_type == EXPR_ALL_EXPR \
		or expression_type == EXPR_NO_EXPR

static func _tags_to_serializable(tags: Array[StringName]) -> Array[String]:
	var result: Array[String] = []
	for tag_name in tags:
		result.append(String(tag_name))
	return result

static func _expressions_to_serializable(expressions: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for expression in expressions:
		if expression != null:
			result.append(expression.to_dict())
	return result
