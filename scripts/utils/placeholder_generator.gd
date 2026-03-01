class_name PlaceholderGenerator
extends Object

static func apply_to_sprite(sprite: Sprite2D, _category: String = "", _type: String = ""):
	if sprite.texture:
		return
	var placeholder = PlaceholderTexture2D.new()
	placeholder.size = Vector2(64, 64)
	sprite.texture = placeholder

static func apply_to_texture_rect(rect: TextureRect, _category: String = "", _type: String = ""):
	if rect.texture:
		return
	var placeholder = PlaceholderTexture2D.new()
	placeholder.size = Vector2(64, 64)
	rect.texture = placeholder
