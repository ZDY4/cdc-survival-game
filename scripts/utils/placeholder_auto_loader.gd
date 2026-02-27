extends Node
# PlaceholderAutoLoader - 自动为缺失纹理的节点应用占位符
# 注意：不使用 class_name 以避免循环引用问题

func _ready():
	# Wait for scene to be fully loaded
	await get_tree().process_frame
	_apply_placeholders_to_current_scene()
	
	# Connect to scene changes
	get_tree().node_added.connect(_on_node_added)

func _apply_placeholders_to_current_scene():
	var current_scene = get_tree().current_scene
	if current_scene:
		_apply_placeholders_recursive(current_scene)

func _apply_placeholders_recursive():
	# Apply placeholder based on node name && type
	if node is Sprite2D:
		_apply_sprite_placeholder(node)
	elif node is TextureRect:
		_apply_texture_rect_placeholder(node)
	
	# Recurse through children
	for child in node.get_children():
		_apply_placeholders_recursive(child)

func _apply_sprite_placeholder():
	if sprite.texture != null:
		return
	
	var node_name = sprite.get_parent().name.to_lower()
	
	# Determine placeholder type based on parent name
	if "door" in node_name:
		PlaceholderGenerator.apply_to_sprite(sprite, "object", "door")
	elif "locker" in node_name || "chest" in node_name:
		PlaceholderGenerator.apply_to_sprite(sprite, "object", "locker")
	elif "bed" in node_name:
		PlaceholderGenerator.apply_to_sprite(sprite, "object", "bed")
	elif "car" in node_name:
		PlaceholderGenerator.apply_to_sprite(sprite, "object", "car")
	elif "trash" in node_name:
		PlaceholderGenerator.apply_to_sprite(sprite, "object", "trash")
	elif "zombie" in node_name || "enemy" in node_name:
		PlaceholderGenerator.apply_to_sprite(sprite, "character", "zombie")
	elif "npc" in node_name:
		PlaceholderGenerator.apply_to_sprite(sprite, "character", "npc")
	elif "player" in node_name:
		PlaceholderGenerator.apply_to_sprite(sprite, "character", "player")
	else:
		PlaceholderGenerator.apply_to_sprite(sprite, "object", "box")

func _apply_texture_rect_placeholder():
	if rect.texture != null:
		return
	
	var node_name = rect.name.to_lower()
	var parent_name = rect.get_parent().name.to_lower()
	
	# Check if this is a background
	if "background" in node_name:
		var location_type = "safehouse"
		if "street_a" in parent_name:
			location_type = "street_a"
		elif "street_b" in parent_name:
			location_type = "street_b"
		elif "street" in parent_name:
			location_type = "street"
		elif "safehouse" in parent_name:
			location_type = "safehouse"
		
		PlaceholderGenerator.apply_to_texture_rect(rect, "background", location_type)

func _on_node_added():
	# Apply placeholder to newly added nodes
	if node is Sprite2D:
		_apply_sprite_placeholder(node)
	elif node is TextureRect:
		_apply_texture_rect_placeholder(node)
