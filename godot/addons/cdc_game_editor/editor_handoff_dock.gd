@tool
extends VBoxContainer

const ContentRegistry = preload("res://scripts/data/content_registry.gd")
const EditorContentPresenter = preload("res://addons/cdc_game_editor/editor_content_presenter.gd")

const SESSION_FILE := "godot_editor.session.json"
const NAVIGATION_FILE := "godot_editor.navigation.json"
const HEARTBEAT_SECONDS := 2.0

var repo_root: String = ""
var handoff_dir: String = ""
var session_path: String = ""
var navigation_path: String = ""
var last_request_id: String = ""
var registry: ContentRegistry
var presenter: EditorContentPresenter

var target_label: Label
var path_label: Label
var status_label: Label
var summary_label: RichTextLabel
var heartbeat_timer: Timer


func _ready() -> void:
	repo_root = ProjectSettings.globalize_path("res://..").simplify_path()
	handoff_dir = repo_root.path_join("tmp/editor_handoff")
	session_path = handoff_dir.path_join(SESSION_FILE)
	navigation_path = handoff_dir.path_join(NAVIGATION_FILE)
	registry = ContentRegistry.new()
	presenter = EditorContentPresenter.new()

	_build_ui()
	_refresh_registry()
	_write_session()
	_read_navigation()

	heartbeat_timer = Timer.new()
	heartbeat_timer.wait_time = HEARTBEAT_SECONDS
	heartbeat_timer.timeout.connect(_on_heartbeat)
	add_child(heartbeat_timer)
	heartbeat_timer.start()


func _exit_tree() -> void:
	_write_session("closed")


func _build_ui() -> void:
	name = "CDC Agent Handoff"
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	var title := Label.new()
	title.text = "CDC Agent Handoff"
	title.add_theme_font_size_override("font_size", 16)
	add_child(title)

	target_label = Label.new()
	target_label.text = "Target: -"
	add_child(target_label)

	path_label = Label.new()
	path_label.text = "Path: -"
	path_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(path_label)

	status_label = Label.new()
	status_label.text = "Status: waiting for navigation request"
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(status_label)

	var refresh_button := Button.new()
	refresh_button.text = "Refresh"
	refresh_button.pressed.connect(_on_refresh_pressed)
	add_child(refresh_button)

	summary_label = RichTextLabel.new()
	summary_label.fit_content = true
	summary_label.scroll_active = true
	summary_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	summary_label.text = "No target selected."
	add_child(summary_label)


func _on_heartbeat() -> void:
	_write_session()
	_read_navigation()


func _on_refresh_pressed() -> void:
	_refresh_registry()
	_read_navigation(true)


func _refresh_registry() -> void:
	var result := registry.load_all()
	if result.has_errors():
		status_label.text = "Status: content load failed"
		summary_label.text = "\n".join(result.errors)
	else:
		status_label.text = "Status: content loaded"


func _write_session(state: String = "active") -> void:
	DirAccess.make_dir_recursive_absolute(handoff_dir)
	var payload := {
		"editor": "godot_editor",
		"state": state,
		"pid": OS.get_process_id(),
		"project_path": ProjectSettings.globalize_path("res://").simplify_path(),
		"updated_at_unix_ms": Time.get_unix_time_from_system() * 1000,
	}
	var file := FileAccess.open(session_path, FileAccess.WRITE)
	if file == null:
		push_warning("failed to write Godot editor session: %s" % error_string(FileAccess.get_open_error()))
		return
	file.store_string(JSON.stringify(payload, "\t"))


func _read_navigation(force: bool = false) -> void:
	if not FileAccess.file_exists(navigation_path):
		return
	var raw := FileAccess.get_file_as_string(navigation_path)
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		status_label.text = "Status: invalid navigation JSON"
		return
	var request: Dictionary = parsed
	var request_id := str(request.get("request_id", ""))
	if not force and request_id == last_request_id:
		return
	last_request_id = request_id
	_apply_navigation(request)


func _apply_navigation(request: Dictionary) -> void:
	var target_kind := str(request.get("target_kind", ""))
	var target_id := str(request.get("target_id", ""))
	target_label.text = "Target: %s %s" % [target_kind, target_id]

	var domain := _domain_for_kind(target_kind)
	if domain.is_empty():
		status_label.text = "Status: unsupported target kind %s" % target_kind
		path_label.text = "Path: -"
		summary_label.text = "Supported kinds: %s." % ", ".join(presenter.supported_kinds())
		return

	var selection := presenter.build_selection(target_kind, target_id, registry, repo_root)
	if not bool(selection.get("ok", false)):
		status_label.text = "Status: %s" % selection.get("status", "failed")
		path_label.text = "Path: -"
		summary_label.text = str(selection.get("message", "Failed to select target."))
		return

	status_label.text = "Status: selected"
	path_label.text = "Path: %s" % selection.get("path", "")
	var sections: Array[String] = [
		str(selection.get("summary", "")),
		str(selection.get("reference_summary", "")),
	]
	for field in ["review_summary", "review_checklist"]:
		var text := str(selection.get(field, ""))
		if not text.is_empty():
			sections.append(text)
	summary_label.text = "\n\n".join(sections)


func _domain_for_kind(kind: String) -> String:
	return presenter.domain_for_kind(kind)
