@tool
class_name MapTilePaletteWindow
extends VBoxContainer

const AssetPathResolver = preload("res://scripts/data/asset_path_resolver.gd")
const ContentRegistry = preload("res://scripts/data/content_registry.gd")
const MapBuilding3D = preload("res://scripts/world/map_building_3d.gd")
const MapBuildingVisuals3D = preload("res://scripts/world/map_building_visuals_3d.gd")
const MapContainer3D = preload("res://scripts/world/map_container_3d.gd")
const MapPickup3D = preload("res://scripts/world/map_pickup_3d.gd")
const MapStaticProp3D = preload("res://scripts/world/map_static_prop_3d.gd")
const MapTransitionTrigger3D = preload("res://scripts/world/map_transition_trigger_3d.gd")
const MapSceneRoot = preload("res://scripts/world/map_scene_root.gd")

const CATEGORY_BUILDING := "Building Tiles"
const CATEGORY_SURFACE := "Surface Tiles"
const CATEGORY_PROPS := "Props"
const CATEGORY_MARKERS := "Markers"
const MARKER_TYPES := [
	{
		"id": "trigger",
		"label": "Transition Trigger",
		"script": MapTransitionTrigger3D,
	},
	{
		"id": "pickup",
		"label": "Pickup",
		"script": MapPickup3D,
	},
	{
		"id": "container",
		"label": "Container",
		"script": MapContainer3D,
	},
]

var registry: ContentRegistry
var palette_items: Array[Dictionary] = []
var selected_item: Dictionary = {}
var rotation_degrees_y := 0
var snap_enabled := true
var scene_root_override: Node
var selected_nodes_override: Array[Node] = []
var undo_redo_override: EditorUndoRedoManager

var status_label: Label
var category_option: OptionButton
var item_list: ItemList
var place_button: Button
var snap_check: CheckBox
var rotation_option: OptionButton
var refresh_button: Button
var rotate_button: Button
var delete_button: Button


func _ready() -> void:
	registry = ContentRegistry.new()
	_build_ui()
	refresh_palette()
	_update_place_button()


func refresh_palette() -> void:
	if registry == null:
		registry = ContentRegistry.new()
	var load_result := registry.load_all()
	palette_items.clear()
	if load_result.has_errors():
		_set_status("Status: failed to load world tile registry")
		for error in load_result.errors:
			push_warning(str(error))
		_rebuild_item_list()
		return

	_collect_world_tile_items()
	_collect_marker_items()
	_rebuild_item_list()
	_set_status("Status: loaded %d palette items" % palette_items.size())


func place_selected_item() -> Dictionary:
	if selected_item.is_empty():
		return _fail("no palette item selected")
	var root := _edited_scene_root()
	if root == null:
		return _fail("open a map scene before placing palette items")
	if not _is_map_scene_root(root):
		return _fail("current scene root is not a map scene")

	var category := str(selected_item.get("category", ""))
	var parent := _placement_parent(category)
	if parent == null:
		return _fail(_missing_parent_message(category))

	var node := _instantiate_selected_item()
	if node == null:
		return _fail("failed to instantiate selected palette item")

	node.name = _unique_child_name(parent, _default_node_name(selected_item))
	_apply_new_node_transform(node, parent)
	_assign_new_node_metadata(node)
	_commit_add_child(parent, node, root, "Place Map Tile Palette Item")
	_select_node(node)
	_set_status("Status: placed %s" % node.name)
	return {"ok": true, "node": node, "parent": parent, "item": selected_item.duplicate(true)}


func rotate_selected_nodes() -> Dictionary:
	var nodes := _selected_editable_nodes()
	if nodes.is_empty():
		return _fail("select a placed map node before rotating")
	var undo_redo := _undo_redo()
	if undo_redo != null:
		undo_redo.create_action("Rotate Map Tile Palette Selection")
		for node in nodes:
			var next_rotation := node.rotation_degrees
			next_rotation.y = rotation_degrees_y
			undo_redo.add_do_property(node, "rotation_degrees", next_rotation)
			undo_redo.add_undo_property(node, "rotation_degrees", node.rotation_degrees)
		undo_redo.commit_action()
	else:
		for node in nodes:
			var next_rotation := node.rotation_degrees
			next_rotation.y = rotation_degrees_y
			node.rotation_degrees = next_rotation
	_set_status("Status: rotated %d node(s)" % nodes.size())
	return {"ok": true, "count": nodes.size()}


func delete_selected_nodes() -> Dictionary:
	var nodes := _selected_editable_nodes()
	if nodes.is_empty():
		return _fail("select a placed map node before deleting")
	var undo_redo := _undo_redo()
	var scene_root := _edited_scene_root()
	if undo_redo != null:
		undo_redo.create_action("Delete Map Tile Palette Selection")
		for node in nodes:
			var parent := node.get_parent()
			if parent == null:
				continue
			undo_redo.add_do_method(parent, "remove_child", node)
			undo_redo.add_undo_method(parent, "add_child", node)
			undo_redo.add_undo_method(self, "_set_owner_recursive", node, scene_root)
		undo_redo.commit_action()
	else:
		for node in nodes:
			var parent := node.get_parent()
			if parent != null:
				parent.remove_child(node)
			node.queue_free()
	_set_status("Status: deleted %d node(s)" % nodes.size())
	return {"ok": true, "count": nodes.size()}


func set_rotation_degrees_y(value: int) -> void:
	var normalized := int(round(float(value) / 90.0)) * 90
	rotation_degrees_y = ((normalized % 360) + 360) % 360
	if rotation_option != null:
		var index := [0, 90, 180, 270].find(rotation_degrees_y)
		if index >= 0:
			rotation_option.select(index)


func set_snap_enabled(enabled: bool) -> void:
	snap_enabled = enabled
	if snap_check != null:
		snap_check.button_pressed = enabled


func setup_test_context(scene_root: Node, selected_nodes: Array[Node] = [], undo_redo: EditorUndoRedoManager = null) -> void:
	scene_root_override = scene_root
	selected_nodes_override = selected_nodes
	undo_redo_override = undo_redo
	_update_place_button()


func select_item_by_id(item_id: String) -> bool:
	for item in palette_items:
		if str(item.get("id", "")) == item_id:
			selected_item = item
			_select_item_in_list(item_id)
			_update_place_button()
			return true
	return false


func _build_ui() -> void:
	name = "CDC Map Tile Palette"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	var title := Label.new()
	title.text = "CDC Map Tile Palette"
	title.add_theme_font_size_override("font_size", 16)
	add_child(title)

	status_label = Label.new()
	status_label.text = "Status: loading palette"
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(status_label)

	var toolbar := HBoxContainer.new()
	add_child(toolbar)

	category_option = OptionButton.new()
	category_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for category in [CATEGORY_BUILDING, CATEGORY_SURFACE, CATEGORY_PROPS, CATEGORY_MARKERS]:
		category_option.add_item(category)
	category_option.item_selected.connect(_on_category_selected)
	toolbar.add_child(category_option)

	refresh_button = Button.new()
	refresh_button.text = "Refresh"
	refresh_button.pressed.connect(refresh_palette)
	toolbar.add_child(refresh_button)

	item_list = ItemList.new()
	item_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	item_list.item_selected.connect(_on_item_selected)
	add_child(item_list)

	var option_bar := HBoxContainer.new()
	add_child(option_bar)

	snap_check = CheckBox.new()
	snap_check.text = "Snap"
	snap_check.button_pressed = snap_enabled
	snap_check.toggled.connect(set_snap_enabled)
	option_bar.add_child(snap_check)

	rotation_option = OptionButton.new()
	for value in [0, 90, 180, 270]:
		rotation_option.add_item("%d deg" % value)
	rotation_option.item_selected.connect(_on_rotation_selected)
	option_bar.add_child(rotation_option)

	place_button = Button.new()
	place_button.text = "Place"
	place_button.pressed.connect(func() -> void:
		place_selected_item()
	)
	option_bar.add_child(place_button)

	rotate_button = Button.new()
	rotate_button.text = "Rotate Selected"
	rotate_button.pressed.connect(rotate_selected_nodes)
	option_bar.add_child(rotate_button)

	delete_button = Button.new()
	delete_button.text = "Delete Selected"
	delete_button.pressed.connect(delete_selected_nodes)
	option_bar.add_child(delete_button)


func _collect_world_tile_items() -> void:
	for record_id in _sorted_keys(registry.get_library("world_tiles")):
		var record: Dictionary = registry.get_library("world_tiles").get(record_id, {})
		var data: Dictionary = _dictionary_or_empty(record.get("data", {}))
		for prototype in _array_or_empty(data.get("prototypes", [])):
			var prototype_data: Dictionary = _dictionary_or_empty(prototype)
			var prototype_id := str(prototype_data.get("id", "")).strip_edges()
			var source: Dictionary = _dictionary_or_empty(prototype_data.get("source", {}))
			var source_path := str(source.get("path", "")).strip_edges()
			if prototype_id.is_empty() or source_path.is_empty():
				continue
			var category := _category_for_prototype(prototype_id)
			if category.is_empty():
				continue
			var resolved := AssetPathResolver.resolve_model_asset(source_path)
			if not bool(resolved.get("ok", false)) or not bool(resolved.get("exists", false)):
				continue
			palette_items.append({
				"id": prototype_id,
				"label": prototype_id.get_file(),
				"category": category,
				"source_path": source_path,
				"resource_path": str(resolved.get("resource_path", "")),
				"record_id": str(record_id),
			})


func _collect_marker_items() -> void:
	for marker in MARKER_TYPES:
		var marker_data: Dictionary = marker
		palette_items.append({
			"id": "marker/%s" % str(marker_data.get("id", "")),
			"label": str(marker_data.get("label", "")),
			"category": CATEGORY_MARKERS,
			"marker_id": str(marker_data.get("id", "")),
			"script": marker_data.get("script"),
		})


func _category_for_prototype(prototype_id: String) -> String:
	if prototype_id.begins_with("building_wall/"):
		return CATEGORY_BUILDING
	if prototype_id.begins_with("surface_placeholder_basic/"):
		return CATEGORY_SURFACE
	if prototype_id.begins_with("props/"):
		return CATEGORY_PROPS
	return ""


func _rebuild_item_list() -> void:
	if item_list == null:
		return
	var current_id := str(selected_item.get("id", ""))
	item_list.clear()
	var category := _selected_category()
	for item in palette_items:
		if str(item.get("category", "")) != category:
			continue
		var index := item_list.add_item(str(item.get("label", item.get("id", ""))))
		item_list.set_item_metadata(index, item)
	selected_item = {}
	if item_list.item_count > 0:
		item_list.select(0)
		selected_item = _dictionary_or_empty(item_list.get_item_metadata(0))
	if not current_id.is_empty():
		_select_item_in_list(current_id)
	_update_place_button()


func _select_item_in_list(item_id: String) -> void:
	if item_list == null:
		return
	for index in range(item_list.item_count):
		var item: Dictionary = _dictionary_or_empty(item_list.get_item_metadata(index))
		if str(item.get("id", "")) == item_id:
			item_list.select(index)
			selected_item = item
			var category := str(item.get("category", ""))
			var category_index := [CATEGORY_BUILDING, CATEGORY_SURFACE, CATEGORY_PROPS, CATEGORY_MARKERS].find(category)
			if category_option != null and category_index >= 0:
				category_option.select(category_index)
			return


func _instantiate_selected_item() -> Node3D:
	var category := str(selected_item.get("category", ""))
	if category == CATEGORY_MARKERS:
		return _instantiate_marker(selected_item)
	if category == CATEGORY_PROPS:
		return _instantiate_static_prop(selected_item)
	var resource_path := str(selected_item.get("resource_path", ""))
	if resource_path.is_empty() or not ResourceLoader.exists(resource_path):
		return null
	var packed: PackedScene = load(resource_path)
	if packed == null:
		return null
	return packed.instantiate() as Node3D


func _instantiate_static_prop(item: Dictionary) -> Node3D:
	var resource_path := str(item.get("resource_path", ""))
	if resource_path.is_empty() or not ResourceLoader.exists(resource_path):
		return null
	var packed: PackedScene = load(resource_path)
	if packed == null:
		return null
	var prop := Node3D.new()
	prop.set_script(MapStaticProp3D)
	prop.set("object_id", _unique_marker_id("prop"))
	prop.set("visual_prototype_id", str(item.get("id", "")))
	var visuals := Node3D.new()
	visuals.name = "Visuals"
	prop.add_child(visuals)
	var visual := packed.instantiate() as Node3D
	if visual == null:
		return null
	visual.name = _unique_child_name(visuals, _default_node_name(item))
	visuals.add_child(visual)
	return prop


func _instantiate_marker(item: Dictionary) -> Node3D:
	var node: Node3D
	var script: GDScript = item.get("script")
	match str(item.get("marker_id", "")):
		"trigger":
			node = Node3D.new()
			node.set_script(script)
			node.set("object_id", _unique_marker_id("transition_trigger"))
		"pickup":
			node = Node3D.new()
			node.set_script(script)
			node.set("object_id", _unique_marker_id("pickup"))
		"container":
			node = Node3D.new()
			node.set_script(script)
			node.set("object_id", _unique_marker_id("container"))
			node.set("display_name", "Container")
		_:
			return null
	return node


func _placement_parent(category: String) -> Node:
	match category:
		CATEGORY_BUILDING, CATEGORY_SURFACE:
			return _selected_building_visuals()
		CATEGORY_PROPS, CATEGORY_MARKERS:
			return _objects_node()
	return null


func _selected_building_visuals() -> Node:
	for node in _selected_nodes():
		var visuals := _building_visuals_from_node(node)
		if visuals != null:
			return visuals
	return null


func _building_visuals_from_node(node: Node) -> Node:
	if node == null:
		return null
	if node.name == "Visuals" and _is_map_building(node.get_parent()):
		return node
	if _is_map_building(node):
		return node.get_node_or_null("Visuals")
	var parent := node.get_parent()
	while parent != null:
		if _is_map_building(parent):
			return parent.get_node_or_null("Visuals")
		parent = parent.get_parent()
	return null


func _objects_node() -> Node:
	var root := _edited_scene_root()
	if root == null:
		return null
	return root.get_node_or_null("Objects")


func _apply_new_node_transform(node: Node3D, parent: Node) -> void:
	var base_position := Vector3.ZERO
	if parent is Node3D:
		base_position = (parent as Node3D).to_local(_selection_world_position())
	if snap_enabled:
		base_position.x = round(base_position.x)
		base_position.z = round(base_position.z)
	node.position = base_position
	node.rotation_degrees.y = rotation_degrees_y


func _selection_world_position() -> Vector3:
	for node in _selected_nodes():
		if node is Node3D:
			return (node as Node3D).global_position
	return Vector3.ZERO


func _assign_new_node_metadata(node: Node3D) -> void:
	var category := str(selected_item.get("category", ""))
	if category != CATEGORY_MARKERS:
		node.set_meta("palette_prototype_id", str(selected_item.get("id", "")))
		node.set_meta("palette_category", category)


func _commit_add_child(parent: Node, node: Node, scene_root: Node, action_name: String) -> void:
	var undo_redo := _undo_redo()
	if undo_redo != null:
		undo_redo.create_action(action_name)
		undo_redo.add_do_method(parent, "add_child", node)
		undo_redo.add_do_method(self, "_set_owner_recursive", node, scene_root)
		undo_redo.add_undo_method(parent, "remove_child", node)
		undo_redo.commit_action()
		return
	parent.add_child(node)
	_set_owner_recursive(node, scene_root)


func _set_owner_recursive(node: Node, scene_root: Node) -> void:
	node.owner = scene_root
	if node.scene_file_path.ends_with(".gltf") or node.scene_file_path.ends_with(".glb") or node.scene_file_path.ends_with(".tscn"):
		return
	for child in node.get_children():
		_set_owner_recursive(child, scene_root)


func _select_node(node: Node) -> void:
	if scene_root_override != null:
		selected_nodes_override = [node]
		return
	if not Engine.is_editor_hint():
		return
	var selection := EditorInterface.get_selection()
	if selection == null:
		return
	selection.clear()
	selection.add_node(node)


func _edited_scene_root() -> Node:
	if scene_root_override != null:
		return scene_root_override
	if Engine.is_editor_hint():
		return EditorInterface.get_edited_scene_root()
	return null


func _selected_nodes() -> Array[Node]:
	if scene_root_override != null:
		return selected_nodes_override
	if Engine.is_editor_hint():
		var nodes: Array[Node] = []
		for node in EditorInterface.get_selection().get_selected_nodes():
			if node is Node:
				nodes.append(node)
		return nodes
	return []


func _selected_editable_nodes() -> Array[Node3D]:
	var output: Array[Node3D] = []
	var root := _edited_scene_root()
	for node in _selected_nodes():
		var node_3d := node as Node3D
		if node_3d == null or node_3d == root:
			continue
		if root != null and not root.is_ancestor_of(node_3d):
			continue
		output.append(node_3d)
	return output


func _undo_redo() -> EditorUndoRedoManager:
	if undo_redo_override != null:
		return undo_redo_override
	if Engine.is_editor_hint():
		return EditorInterface.get_editor_undo_redo()
	return null


func _is_map_scene_root(root: Node) -> bool:
	if root == null:
		return false
	if root.get_script() == MapSceneRoot:
		return true
	if root.has_method("to_definition"):
		return true
	var map_id: Variant = root.get("map_id")
	return typeof(map_id) == TYPE_STRING and not str(map_id).strip_edges().is_empty()


func _is_map_building(node: Node) -> bool:
	return node != null and node.get_script() == MapBuilding3D


func _default_node_name(item: Dictionary) -> String:
	var category := str(item.get("category", ""))
	if category == CATEGORY_MARKERS:
		return str(item.get("marker_id", "marker"))
	var id := str(item.get("id", "tile"))
	return id.replace("/", "_")


func _unique_child_name(parent: Node, base_name: String) -> String:
	var clean := base_name.strip_edges()
	if clean.is_empty():
		clean = "PaletteItem"
	if parent.get_node_or_null(clean) == null:
		return clean
	var index := 2
	while parent.get_node_or_null("%s_%d" % [clean, index]) != null:
		index += 1
	return "%s_%d" % [clean, index]


func _unique_marker_id(prefix: String) -> String:
	var objects := _objects_node()
	var index := 1
	while objects != null and _objects_node_has_id_or_name(objects, "%s_%02d" % [prefix, index]):
		index += 1
	return "%s_%02d" % [prefix, index]


func _objects_node_has_id_or_name(objects: Node, value: String) -> bool:
	if objects.get_node_or_null(value) != null:
		return true
	for child in objects.get_children():
		if str(child.get("object_id")) == value:
			return true
	return false


func _missing_parent_message(category: String) -> String:
	match category:
		CATEGORY_BUILDING, CATEGORY_SURFACE:
			return "select a MapBuilding3D or its Visuals node before placing building/surface tiles"
		CATEGORY_PROPS, CATEGORY_MARKERS:
			return "current map scene has no Objects node"
	return "no valid placement parent"


func _update_place_button() -> void:
	if place_button == null:
		return
	var can_place := not selected_item.is_empty()
	var root := _edited_scene_root()
	if can_place:
		can_place = root != null and _is_map_scene_root(root)
	if can_place:
		can_place = _placement_parent(str(selected_item.get("category", ""))) != null
	place_button.disabled = not can_place


func _on_category_selected(_index: int) -> void:
	_rebuild_item_list()


func _on_item_selected(index: int) -> void:
	selected_item = _dictionary_or_empty(item_list.get_item_metadata(index))
	_update_place_button()


func _on_rotation_selected(index: int) -> void:
	var values := [0, 90, 180, 270]
	if index >= 0 and index < values.size():
		set_rotation_degrees_y(values[index])


func _selected_category() -> String:
	if category_option == null or category_option.item_count <= 0:
		return CATEGORY_BUILDING
	return category_option.get_item_text(category_option.selected)


func _fail(message: String) -> Dictionary:
	_set_status("Status: %s" % message)
	return {"ok": false, "message": message}


func _set_status(text: String) -> void:
	if status_label != null:
		status_label.text = text


func _sorted_keys(input: Dictionary) -> Array[String]:
	var keys: Array[String] = []
	for key in input.keys():
		keys.append(str(key))
	keys.sort()
	return keys


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
