extends RefCounted


static func texture_from_asset(asset: Dictionary) -> Texture2D:
	var resource_path := resource_path_from_asset(asset)
	if resource_path.is_empty():
		return null
	if resource_path.get_extension().to_lower() == "svg":
		return _svg_texture_from_file(resource_path)
	var resource := load(resource_path)
	if resource is Texture2D:
		return resource as Texture2D
	return null


static func resource_path_from_asset(asset: Dictionary) -> String:
	if not bool(asset.get("ok", false)) or not bool(asset.get("exists", false)):
		return ""
	return str(asset.get("resource_path", ""))


static func _svg_texture_from_file(resource_path: String) -> Texture2D:
	var file := FileAccess.open(resource_path, FileAccess.READ)
	if file == null:
		return null
	var image := Image.new()
	var error := image.load_svg_from_string(file.get_as_text())
	if error != OK:
		return null
	return ImageTexture.create_from_image(image)
