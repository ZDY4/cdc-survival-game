extends SceneTree

const ContentRegistry = preload("res://scripts/data/content_registry.gd")


func _init() -> void:
	var registry := ContentRegistry.new()
	var result := registry.load_all()
	var summary := registry.summary()

	print("Godot content validation summary:")
	print(JSON.stringify(summary, "\t"))

	for warning in result.warnings:
		push_warning(warning)
	for error in result.errors:
		printerr(error)

	if result.has_errors():
		printerr("Godot content validation failed: %d error(s), %d warning(s)" % [result.errors.size(), result.warnings.size()])
		quit(1)
		return

	print("Godot content validation passed: %d warning(s)" % result.warnings.size())
	quit(0)
