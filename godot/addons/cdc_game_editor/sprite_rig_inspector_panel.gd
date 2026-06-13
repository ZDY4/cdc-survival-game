@tool
extends VBoxContainer

var target_rig: CharacterSpriteRig
var editor_plugin: EditorPlugin
var status_label: Label
var summary_label: Label
var _ui_built := false


func setup(rig: CharacterSpriteRig, plugin: EditorPlugin) -> void:
	target_rig = rig
	editor_plugin = plugin


func _ready() -> void:
	if _ui_built:
		_refresh_summary()
		return
	_ui_built = true
	name = "SpriteRigInspectorPanel"
	add_theme_constant_override("separation", 6)
	var title := Label.new()
	title.text = "Sprite Rig"
	add_child(title)
	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(status_label)
	summary_label = Label.new()
	summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(summary_label)
	var open_button := Button.new()
	open_button.text = "Open Current Rig Editor"
	open_button.pressed.connect(_on_open_pressed)
	add_child(open_button)
	_refresh_summary()


func _refresh_summary() -> void:
	if target_rig == null:
		status_label.text = "No CharacterSpriteRig selected."
		summary_label.text = ""
		return
	var profile: Resource = target_rig.profile
	if profile == null:
		status_label.text = "Profile: <missing>"
		summary_label.text = "Parts: 0"
		return
	status_label.text = "Profile: %s" % (profile.resource_path if not profile.resource_path.is_empty() else "<embedded>")
	var sprites: Array = profile.get("sprites") if typeof(profile.get("sprites")) == TYPE_ARRAY else []
	var total := 0
	var missing := 0
	var yaw_step := max(1, int(profile.get("yaw_step_degrees")))
	var pitch_step := max(1, int(profile.get("pitch_step_degrees")))
	for part_value in sprites:
		var part := part_value as Resource
		if part == null:
			continue
		var textures: Dictionary = part.get("angle_to_texture") if typeof(part.get("angle_to_texture")) == TYPE_DICTIONARY else {}
		for yaw in range(0, 360, yaw_step):
			var pitch := -90
			while pitch <= 90:
				total += 1
				if not textures.has(_direction_key(yaw, pitch)) or textures.get(_direction_key(yaw, pitch)) == null:
					missing += 1
				pitch += pitch_step
	summary_label.text = "Parts: %d | Configured: %d / %d | Missing: %d" % [sprites.size(), total - missing, total, missing]


func _direction_key(yaw: int, pitch: int) -> String:
	if target_rig != null and target_rig.profile != null and target_rig.profile.has_method("direction_key_for"):
		return str(target_rig.profile.call("direction_key_for", yaw, pitch))
	var pitch_label := str(pitch) if pitch >= 0 else "neg%s" % abs(pitch)
	return "yaw_%03d_pitch_%s" % [yaw, pitch_label]


func _on_open_pressed() -> void:
	if editor_plugin == null or target_rig == null:
		return
	editor_plugin.call("open_sprite_rig_inspector_for_rig", target_rig)
