extends RefCounted
## GameplayTagContainer - Stores explicit gameplay tags for an entity/context.

class_name GameplayTagContainer

var _explicit_tags: Dictionary = {}

func add_tag(tag: StringName) -> void:
	if String(tag).is_empty():
		return
	_explicit_tags[tag] = true

func remove_tag(tag: StringName) -> void:
	if _explicit_tags.has(tag):
		_explicit_tags.erase(tag)

func has_tag(tag: StringName, exact: bool = false) -> bool:
	var requested_tag_text: String = String(tag)
	if requested_tag_text.is_empty():
		return false
	if exact:
		return _explicit_tags.has(tag)

	var manager: Node = _get_manager()
	for explicit_tag in _explicit_tags.keys():
		if explicit_tag == tag:
			return true
		if manager and manager.has_method("matches_tag"):
			if bool(manager.call("matches_tag", explicit_tag, tag, false)):
				return true
		else:
			var explicit_text: String = String(explicit_tag)
			if explicit_text.begins_with("%s." % requested_tag_text):
				return true
	return false

func has_any(tags: Array[StringName], exact: bool = false) -> bool:
	for tag_name in tags:
		if has_tag(tag_name, exact):
			return true
	return false

func has_all(tags: Array[StringName], exact: bool = false) -> bool:
	for tag_name in tags:
		if not has_tag(tag_name, exact):
			return false
	return true

func clear() -> void:
	_explicit_tags.clear()

func is_empty() -> bool:
	return _explicit_tags.is_empty()

func get_explicit_tags() -> Array[StringName]:
	var sorted_text: Array[String] = []
	for tag_name in _explicit_tags.keys():
		sorted_text.append(String(tag_name))
	sorted_text.sort()
	var result: Array[StringName] = []
	for tag_text in sorted_text:
		result.append(StringName(tag_text))
	return result

func duplicate_container():
	var result = self.get_script().new()
	for tag_name in _explicit_tags.keys():
		result.add_tag(tag_name)
	return result

func _get_manager() -> Node:
	var loop: MainLoop = Engine.get_main_loop()
	if not (loop is SceneTree):
		return null
	var tree: SceneTree = loop
	if tree.root == null:
		return null
	return tree.root.get_node_or_null("GameplayTags")
