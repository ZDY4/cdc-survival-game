@tool
extends EditorPlugin

const AUTOLOAD_NAME: String = "GameplayTags"
const MANAGER_SCRIPT_PATH: String = "res://addons/gameplay_tags/runtime/gameplay_tags_manager.gd"
const DOCK_SCRIPT_PATH: String = "res://addons/gameplay_tags/editor/gameplay_tags_dock.gd"

var _dock: Control = null
var _autoload_added_by_plugin: bool = false

func _enter_tree() -> void:
	_ensure_autoload_singleton()
	_create_dock()
	call_deferred("_bind_manager_to_dock")

func _exit_tree() -> void:
	_remove_dock()
	_remove_autoload_singleton_if_needed()

func _ensure_autoload_singleton() -> void:
	var setting_key: String = "autoload/%s" % AUTOLOAD_NAME
	if ProjectSettings.has_setting(setting_key):
		var configured_path: String = str(ProjectSettings.get_setting(setting_key))
		var clean_path: String = configured_path.trim_prefix("*")
		if clean_path != MANAGER_SCRIPT_PATH:
			push_warning(
				"[Gameplay Tags] Autoload '%s' already exists at %s, expected %s." %
				[AUTOLOAD_NAME, configured_path, MANAGER_SCRIPT_PATH]
			)
		return

	add_autoload_singleton(AUTOLOAD_NAME, MANAGER_SCRIPT_PATH)
	_autoload_added_by_plugin = true
	ProjectSettings.save()

func _remove_autoload_singleton_if_needed() -> void:
	if not _autoload_added_by_plugin:
		return
	remove_autoload_singleton(AUTOLOAD_NAME)
	ProjectSettings.save()
	_autoload_added_by_plugin = false

func _create_dock() -> void:
	var dock_script: Script = load(DOCK_SCRIPT_PATH)
	if dock_script == null:
		push_error("[Gameplay Tags] Failed to load dock script at %s" % DOCK_SCRIPT_PATH)
		return

	var dock_instance: Variant = dock_script.new()
	if not (dock_instance is Control):
		push_error("[Gameplay Tags] Dock script must extend Control.")
		return

	_dock = dock_instance
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)

func _remove_dock() -> void:
	if _dock == null:
		return
	remove_control_from_docks(_dock)
	_dock.queue_free()
	_dock = null

func _bind_manager_to_dock() -> void:
	if _dock == null:
		return

	var manager: Node = _get_manager_node()
	if manager and manager.has_method("reload_tags"):
		manager.call("reload_tags")

	if _dock.has_method("set_manager"):
		_dock.call("set_manager", manager)

func _get_manager_node() -> Node:
	var base_control: Control = get_editor_interface().get_base_control()
	if base_control == null:
		return null
	var tree: SceneTree = base_control.get_tree()
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(AUTOLOAD_NAME)
