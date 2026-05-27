extends Node

const ContentRegistry = preload("res://scripts/data/content_registry.gd")

var content_registry: ContentRegistry


func load_content() -> Dictionary:
	content_registry = ContentRegistry.new()
	var result := content_registry.load_all()
	return {
		"ok": not result.has_errors(),
		"summary": content_registry.summary(),
		"errors": result.errors,
		"warnings": result.warnings,
	}
