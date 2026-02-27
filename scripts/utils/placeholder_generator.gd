class_name PlaceholderGenerator
extends Object

static func apply_to_sprite():
	if sprite.texture:
		return
	var placeholder = PlaceholderTexture2D.new()
	placeholder.size = Vector2(64, 64)
	sprite.texture = placeholder

static func apply_to_texture_rect():
	if rect.texture:
		return
	var placeholder = PlaceholderTexture2D.new()
	placeholder.size = Vector2(64, 64)
	rect.texture = placeholder
