extends RefCounted
## GameplayTagStackContainer - Tracks counted stacks per gameplay tag.

class_name GameplayTagStackContainer

var _tag_stacks: Dictionary = {}

func add_stack(tag: StringName, count: int = 1) -> int:
	if String(tag).is_empty():
		return 0
	if count <= 0:
		return get_stack_count(tag)

	var current_count: int = int(_tag_stacks.get(tag, 0))
	var new_count: int = current_count + count
	_tag_stacks[tag] = new_count
	return new_count

func remove_stack(tag: StringName, count: int = 1) -> int:
	if String(tag).is_empty():
		return 0
	if count <= 0:
		return get_stack_count(tag)
	if not _tag_stacks.has(tag):
		return 0

	var current_count: int = int(_tag_stacks[tag])
	var new_count: int = maxi(current_count - count, 0)
	if new_count == 0:
		_tag_stacks.erase(tag)
	else:
		_tag_stacks[tag] = new_count
	return new_count

func clear_stack(tag: StringName) -> void:
	if _tag_stacks.has(tag):
		_tag_stacks.erase(tag)

func clear() -> void:
	_tag_stacks.clear()

func get_stack_count(tag: StringName) -> int:
	return int(_tag_stacks.get(tag, 0))

func has_tag(tag: StringName, exact: bool = false) -> bool:
	var requested_tag_text: String = String(tag)
	if requested_tag_text.is_empty():
		return false
	if exact:
		return get_stack_count(tag) > 0

	var manager: Node = _get_manager()
	for explicit_tag in _tag_stacks.keys():
		var stack_count: int = int(_tag_stacks[explicit_tag])
		if stack_count <= 0:
			continue
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

func get_explicit_tags() -> Array[StringName]:
	var sorted_text: Array[String] = []
	for tag_name in _tag_stacks.keys():
		if int(_tag_stacks[tag_name]) > 0:
			sorted_text.append(String(tag_name))
	sorted_text.sort()
	var result: Array[StringName] = []
	for tag_text in sorted_text:
		result.append(StringName(tag_text))
	return result

func to_container() -> GameplayTagContainer:
	var container: GameplayTagContainer = GameplayTagContainer.new()
	for tag_name in _tag_stacks.keys():
		if int(_tag_stacks[tag_name]) > 0:
			container.add_tag(tag_name)
	return container

func _get_manager() -> Node:
	var loop: MainLoop = Engine.get_main_loop()
	if not (loop is SceneTree):
		return null
	var tree: SceneTree = loop
	if tree.root == null:
		return null
	return tree.root.get_node_or_null("GameplayTags")
