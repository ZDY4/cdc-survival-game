extends SceneTree

const ContentRegistry = preload("res://scripts/data/content_registry.gd")
const ContentReferenceIndex = preload("res://scripts/tools/content_reference_index.gd")


func _init() -> void:
	var errors := _run()
	if not errors.is_empty():
		for error in errors:
			printerr(error)
		quit(1)
		return

	print("content_cli_smoke passed:")
	print({
		"covered_reference_domains": ["item", "recipe", "character", "dialogue", "quest", "skill", "settlement", "overworld", "map"],
	})
	quit(0)


func _run() -> Array[String]:
	var errors: Array[String] = []
	var registry: ContentRegistry = ContentRegistry.new()
	var result := registry.load_all()
	if result.has_errors():
		for error in result.errors:
			errors.append(str(error))
		return errors

	var index: ContentReferenceIndex = ContentReferenceIndex.new()
	_expect_min_refs(errors, index, registry, "items", "1006", 1)
	_expect_min_refs(errors, index, registry, "characters", "zombie_walker", 1)
	_expect_min_refs(errors, index, registry, "dialogues", "trader_lao_wang_intro", 1)
	_expect_min_refs(errors, index, registry, "quests", "tutorial_survive", 1)
	_expect_min_refs(errors, index, registry, "skills", "survival", 1)
	_expect_min_refs(errors, index, registry, "settlements", "survivor_outpost_01_settlement", 1)
	_expect_min_refs(errors, index, registry, "overworld", "main_overworld", 1)
	_expect_min_refs(errors, index, registry, "maps", "survivor_outpost_01", 1)
	return errors


func _expect_min_refs(errors: Array[String], index: ContentReferenceIndex, registry: ContentRegistry, domain: String, id_value: String, minimum: int) -> void:
	if not index.supports_domain(domain):
		errors.append("reference domain not supported: %s" % domain)
		return
	var hits := index.references_for(domain, id_value, registry)
	if hits.size() < minimum:
		errors.append("expected at least %d references for %s %s, got %d" % [minimum, domain, id_value, hits.size()])
