@tool
extends Window

const AI_SETTINGS := preload("res://addons/cdc_game_editor/ai/ai_settings.gd")
const REPOSITORY_SCRIPT := preload("res://addons/cdc_game_editor/ai/editor_data_repository.gd")
const CONTEXT_BUILDER_SCRIPT := preload("res://addons/cdc_game_editor/ai/context_builder.gd")
const OPENAI_PROVIDER_SCRIPT := preload("res://addons/cdc_game_editor/ai/providers/openai_compatible_provider.gd")

const ADAPTER_SCRIPTS := {
	"item": preload("res://addons/cdc_game_editor/ai/adapters/item_ai_editor_adapter.gd"),
	"character": preload("res://addons/cdc_game_editor/ai/adapters/character_ai_editor_adapter.gd"),
	"dialog": preload("res://addons/cdc_game_editor/ai/adapters/dialog_ai_editor_adapter.gd"),
	"quest": preload("res://addons/cdc_game_editor/ai/adapters/quest_ai_editor_adapter.gd")
}

var editor_plugin: EditorPlugin = null
var host_editor: Object = null
var data_type: String = ""
var provider_override: Variant = null

var last_request_meta: Dictionary = {}
var diff_summary: Dictionary = {}
var validation_errors: Array[String] = []
var provider_error: String = ""

var _repository: RefCounted = null
var _context_builder: RefCounted = null
var _provider: Node = null
var _adapter: RefCounted = null
var _current_draft: Dictionary = {}
var _current_request: Dictionary = {}
var _is_busy := false
var _review_warnings: Array[String] = []

var _type_value_label: Label
var _target_value_label: Label
var _mode_option: OptionButton
var _main_prompt_input: TextEdit
var _adjustment_prompt_input: TextEdit
var _summary_output: TextEdit
var _record_json_output: TextEdit
var _validation_output: TextEdit
var _raw_output: TextEdit
var _current_snapshot_output: TextEdit
var _draft_snapshot_output: TextEdit
var _diff_output: TextEdit
var _prompt_debug_output: TextEdit
var _prompt_debug_toggle: CheckBox
var _generate_button: Button
var _refine_button: Button
var _apply_button: Button
var _copy_button: Button
var _discard_button: Button
var _status_label: Label
var _review_tags_label: Label
var _review_warning_label: Label
var _risk_label: Label


func _ready() -> void:
	title = "CDC AI 生成"
	min_size = Vector2i(1180, 920)
	close_requested.connect(hide)
	_repository = REPOSITORY_SCRIPT.new()
	_context_builder = CONTEXT_BUILDER_SCRIPT.new(_repository)
	_setup_ui()
	_set_status("配置提示词后即可生成草稿")
	_refresh_action_buttons()


func configure(
	target_host_editor: Object,
	target_editor_plugin: EditorPlugin,
	target_data_type: String,
	target_provider_override: Variant = null
) -> void:
	host_editor = target_host_editor
	editor_plugin = target_editor_plugin
	data_type = target_data_type.strip_edges().to_lower()
	provider_override = target_provider_override
	_recreate_provider_if_needed()
	_create_adapter()
	_refresh_header()


func open_panel() -> void:
	_refresh_header()
	_refresh_mode_default()
	show()
	grab_focus()


func set_provider_override(value: Variant) -> void:
	provider_override = value
	_recreate_provider_if_needed()


func _setup_ui() -> void:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 12
	scroll.offset_top = 12
	scroll.offset_right = -12
	scroll.offset_bottom = -12
	add_child(scroll)

	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.custom_minimum_size = Vector2(1120, 0)
	root.add_theme_constant_override("separation", 8)
	scroll.add_child(root)

	var meta_grid := GridContainer.new()
	meta_grid.columns = 2
	root.add_child(meta_grid)

	meta_grid.add_child(_make_label("目标类型"))
	_type_value_label = _make_label("-")
	meta_grid.add_child(_type_value_label)

	meta_grid.add_child(_make_label("目标ID"))
	_target_value_label = _make_label("-")
	meta_grid.add_child(_target_value_label)

	meta_grid.add_child(_make_label("生成模式"))
	_mode_option = OptionButton.new()
	_mode_option.add_item("新建")
	_mode_option.set_item_metadata(0, "create")
	_mode_option.add_item("基于当前记录调整")
	_mode_option.set_item_metadata(1, "revise")
	meta_grid.add_child(_mode_option)

	root.add_child(_make_label("主提示词"))
	_main_prompt_input = TextEdit.new()
	_main_prompt_input.custom_minimum_size = Vector2(0, 110)
	_main_prompt_input.placeholder_text = "描述你希望 AI 生成什么样的角色、任务、对话或物品..."
	root.add_child(_main_prompt_input)

	root.add_child(_make_label("调整提示词"))
	_adjustment_prompt_input = TextEdit.new()
	_adjustment_prompt_input.custom_minimum_size = Vector2(0, 90)
	_adjustment_prompt_input.placeholder_text = "如果要在当前草稿基础上微调，请写在这里。"
	root.add_child(_adjustment_prompt_input)

	var button_row := HBoxContainer.new()
	root.add_child(button_row)

	_generate_button = Button.new()
	_generate_button.text = "生成草稿"
	_generate_button.pressed.connect(_on_generate_pressed)
	button_row.add_child(_generate_button)

	_refine_button = Button.new()
	_refine_button.text = "基于当前草稿重试"
	_refine_button.pressed.connect(_on_refine_pressed)
	button_row.add_child(_refine_button)

	_apply_button = Button.new()
	_apply_button.text = "应用到编辑器"
	_apply_button.pressed.connect(_on_apply_pressed)
	button_row.add_child(_apply_button)

	_copy_button = Button.new()
	_copy_button.text = "复制 JSON"
	_copy_button.pressed.connect(_on_copy_pressed)
	button_row.add_child(_copy_button)

	_discard_button = Button.new()
	_discard_button.text = "丢弃草稿"
	_discard_button.pressed.connect(_on_discard_pressed)
	button_row.add_child(_discard_button)

	_review_tags_label = _make_wrap_label("")
	root.add_child(_review_tags_label)

	_review_warning_label = _make_wrap_label("")
	_review_warning_label.modulate = Color(0.95, 0.8, 0.35)
	root.add_child(_review_warning_label)

	_risk_label = _make_wrap_label("风险级别: -")
	root.add_child(_risk_label)

	var snapshot_split := HSplitContainer.new()
	snapshot_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	snapshot_split.custom_minimum_size = Vector2(0, 220)
	root.add_child(snapshot_split)

	var current_box := VBoxContainer.new()
	snapshot_split.add_child(current_box)
	current_box.add_child(_make_label("Current Record Snapshot"))
	_current_snapshot_output = _make_readonly_text_edit(220)
	current_box.add_child(_current_snapshot_output)

	var draft_box := VBoxContainer.new()
	snapshot_split.add_child(draft_box)
	draft_box.add_child(_make_label("Draft Record Snapshot"))
	_draft_snapshot_output = _make_readonly_text_edit(220)
	draft_box.add_child(_draft_snapshot_output)

	root.add_child(_make_label("Diff Preview"))
	_diff_output = _make_readonly_text_edit(170)
	root.add_child(_diff_output)

	root.add_child(_make_label("摘要"))
	_summary_output = _make_readonly_text_edit(70)
	root.add_child(_summary_output)

	root.add_child(_make_label("Record JSON"))
	_record_json_output = _make_readonly_text_edit(220)
	root.add_child(_record_json_output)

	root.add_child(_make_label("校验结果"))
	_validation_output = _make_readonly_text_edit(120)
	root.add_child(_validation_output)

	root.add_child(_make_label("原始响应 / 错误"))
	_raw_output = _make_readonly_text_edit(120)
	root.add_child(_raw_output)

	_prompt_debug_toggle = CheckBox.new()
	_prompt_debug_toggle.text = "显示 Prompt 调试信息"
	_prompt_debug_toggle.toggled.connect(_on_prompt_debug_toggled)
	root.add_child(_prompt_debug_toggle)

	_prompt_debug_output = _make_readonly_text_edit(140)
	_prompt_debug_output.visible = false
	root.add_child(_prompt_debug_output)

	_status_label = _make_wrap_label("")
	root.add_child(_status_label)


func _recreate_provider_if_needed() -> void:
	if _provider != null and is_instance_valid(_provider):
		_provider.queue_free()
	_provider = null
	if provider_override != null:
		return
	_provider = OPENAI_PROVIDER_SCRIPT.new()
	add_child(_provider)


func _create_adapter() -> void:
	_adapter = null
	if not ADAPTER_SCRIPTS.has(data_type):
		return
	_adapter = ADAPTER_SCRIPTS[data_type].new()
	_adapter.setup(host_editor, editor_plugin, _repository, _context_builder, data_type)


func _refresh_header() -> void:
	if _type_value_label == null:
		return
	_type_value_label.text = data_type if not data_type.is_empty() else "-"
	_target_value_label.text = _get_current_target_id()


func _refresh_mode_default() -> void:
	var has_current := not _get_current_record().is_empty()
	_mode_option.selected = 1 if has_current else 0


func _get_current_mode() -> String:
	return str(_mode_option.get_item_metadata(_mode_option.selected))


func _get_current_target_id() -> String:
	if host_editor != null and host_editor.has_method("build_ai_seed_context"):
		var seed := host_editor.call("build_ai_seed_context")
		if seed is Dictionary:
			return str((seed as Dictionary).get("target_id", "")).strip_edges()
	return ""


func _get_current_record() -> Dictionary:
	if host_editor != null and host_editor.has_method("build_ai_seed_context"):
		var seed := host_editor.call("build_ai_seed_context")
		if seed is Dictionary:
			var current_record := (seed as Dictionary).get("current_record", {})
			if current_record is Dictionary:
				return (current_record as Dictionary).duplicate(true)
	return {}


func _build_request_payload(include_previous_draft: bool) -> Dictionary:
	var mode := _get_current_mode()
	var target_id := _get_current_target_id()
	var current_record := _get_current_record()
	if mode == "create":
		current_record = {}
	var request: Dictionary = {
		"data_type": data_type,
		"mode": mode,
		"target_id": target_id,
		"user_prompt": _main_prompt_input.text.strip_edges(),
		"adjustment_prompt": _adjustment_prompt_input.text.strip_edges(),
		"current_record": current_record
	}
	if include_previous_draft and not _current_draft.is_empty():
		request["previous_draft"] = _current_draft.get("record", {})
		request["previous_validation_errors"] = _collect_validation_lines()
	return request


func _build_prompt_payload(request: Dictionary, context: Dictionary) -> Dictionary:
	var rules: Array[String] = []
	if _adapter != null and _adapter.has_method("get_generation_rules"):
		rules = _adapter.get_generation_rules()

	var system_prompt := "\n\n".join([
		"[输出协议]\n%s" % "\n".join([
			"你正在为 Godot 生存游戏编辑器生成结构化内容。",
			"只能输出一个 JSON 对象，不能输出 Markdown、解释或代码块。",
			"输出必须严格遵守合同：{\"record_type\":\"item|character|dialog|quest\",\"operation\":\"create|revise\",\"target_id\":\"string\",\"summary\":\"string\",\"warnings\":[\"string\"],\"record\":{}}。",
			"record 必须是该类型最终落盘 JSON 格式，而不是表单子集。",
			"不得引用上下文中不存在的 ID；如果确实需要新 ID，必须贴合项目现有命名风格。"
		]),
		"[类型约束]\n%s" % "\n".join(rules + _build_additional_type_constraints()),
		"[最小修改原则]\n%s" % "\n".join(_build_minimal_change_rules(request))
	])

	last_request_meta = _build_request_meta(request, context, rules)
	var user_payload: Dictionary = {
		"request": request,
		"context": context
	}
	return {
		"provider_config": AI_SETTINGS.get_provider_config(editor_plugin),
		"temperature": 0.25,
		"max_tokens": 2200,
		"messages": [
			{"role": "system", "content": system_prompt},
			{"role": "user", "content": JSON.stringify(user_payload, "\t")}
		]
	}


func _build_additional_type_constraints() -> Array[String]:
	match data_type:
		"dialog":
			return [
				"如果新增节点，必须补全 next / true_next / false_next / options[].next 以及 connections。",
				"如果保留旧节点，不得无故断开原有关键路径，除非用户明确要求重构。"
			]
		"quest":
			return [
				"如果新增 flow 节点，必须补全连接信息和可达路径。",
				"如果保留旧节点，不得无故断开 start 到 end 的关键路径，除非用户明确要求重构。"
			]
		_:
			return []


func _build_minimal_change_rules(request: Dictionary) -> Array[String]:
	var rules: Array[String] = [
		"优先保持世界观、命名风格、文案语气与上下文样本一致。"
	]
	if str(request.get("mode", "create")) == "revise":
		rules.append_array([
			"未被用户提到的字段尽量保持不变。",
			"禁止随意重命名主 ID、删除节点、移除技能树、替换现有引用，除非用户明确要求。",
			"如果上一次草稿和本地校验错误已提供，请以最小修改方式修正。"
		])
	else:
		rules.append("新建模式下优先复用现有引用集合，不要发明新的外部依赖 ID。")
	return rules


func _build_request_meta(request: Dictionary, context: Dictionary, rules: Array[String]) -> Dictionary:
	return {
		"data_type": data_type,
		"mode": str(request.get("mode", "create")),
		"target_id": str(request.get("target_id", "")),
		"provider": {
			"base_url": AI_SETTINGS.get_base_url(editor_plugin),
			"model": AI_SETTINGS.get_model(editor_plugin)
		},
		"context_stats": context.get("context_stats", {}),
		"truncation": context.get("truncation", {}),
		"allowed_reference_groups": (context.get("allowed_reference_ids", {}) as Dictionary).keys(),
		"suggested_reference_groups": (context.get("suggested_reference_ids", {}) as Dictionary).keys(),
		"rule_count": rules.size() + _build_additional_type_constraints().size() + _build_minimal_change_rules(request).size()
	}


func _set_busy(is_busy: bool) -> void:
	_is_busy = is_busy
	_refresh_action_buttons()


func _refresh_action_buttons() -> void:
	var can_refine := not _current_draft.is_empty()
	var has_empty_record := _has_empty_record(_current_draft)
	var can_apply := (
		not _current_draft.is_empty()
		and validation_errors.is_empty()
		and provider_error.is_empty()
		and not has_empty_record
	)
	_generate_button.disabled = _is_busy
	_refine_button.disabled = _is_busy or not can_refine
	_copy_button.disabled = _is_busy or _current_draft.is_empty()
	_apply_button.disabled = _is_busy or not can_apply
	_apply_button.text = (
		"确认应用高风险变更"
		if str(diff_summary.get("risk_level", "low")) == "high"
		else "应用到编辑器"
	)


func _on_generate_pressed() -> void:
	await _run_generation(false)


func _on_refine_pressed() -> void:
	await _run_generation(true)


func _run_generation(include_previous_draft: bool) -> void:
	if _adapter == null:
		_set_status("AI 适配器未初始化")
		return
	if _main_prompt_input.text.strip_edges().is_empty():
		_set_status("请先填写主提示词")
		return

	_set_busy(true)
	_set_status("正在请求 AI 生成草稿...")
	_current_request = _build_request_payload(include_previous_draft)
	var context: Dictionary = _adapter.build_context(_current_request)
	var payload := _build_prompt_payload(_current_request, context)
	_render_prompt_debug()

	var provider_result: Dictionary = {}
	if provider_override != null and provider_override.has_method("generate_request"):
		provider_result = await provider_override.generate_request(payload)
	else:
		provider_result = await _provider.generate_request(payload)
	_set_busy(false)

	if not bool(provider_result.get("ok", false)):
		_handle_provider_failure(provider_result)
		return

	var draft: Dictionary = provider_result.get("data", {})
	_current_draft = draft.duplicate(true)
	provider_error = ""
	validation_errors = _validate_draft(draft)
	diff_summary = _summarize_diff(_current_request, draft)
	_review_warnings = _build_review_warnings(_current_request, diff_summary)
	_render_draft_outputs(provider_result)
	_refresh_action_buttons()
	_set_status("AI 草稿已生成，请先审阅差异后再应用")


func _handle_provider_failure(provider_result: Dictionary) -> void:
	provider_error = _normalize_provider_error(provider_result)
	validation_errors = []
	diff_summary = {}
	_review_warnings = []
	_current_draft.clear()
	_summary_output.text = ""
	_record_json_output.text = ""
	_current_snapshot_output.text = JSON.stringify(_current_request.get("current_record", {}), "\t")
	_draft_snapshot_output.text = "{}"
	_diff_output.text = "暂无草稿可预览"
	_validation_output.text = provider_error
	_raw_output.text = str(provider_result.get("raw_text", ""))
	_review_tags_label.text = "预览标签: Provider Error"
	_review_warning_label.text = ""
	_risk_label.text = "风险级别: -"
	_render_prompt_debug()
	_refresh_action_buttons()
	_set_status("AI 生成失败")


func _render_draft_outputs(provider_result: Dictionary) -> void:
	var record: Dictionary = _current_draft.get("record", {})
	_summary_output.text = str(_current_draft.get("summary", ""))
	_record_json_output.text = JSON.stringify(record, "\t")
	_current_snapshot_output.text = JSON.stringify(_current_request.get("current_record", {}), "\t")
	_draft_snapshot_output.text = JSON.stringify(record, "\t")
	_validation_output.text = (
		"\n".join(validation_errors) if not validation_errors.is_empty() else "校验通过"
	)
	_raw_output.text = str(provider_result.get("raw_text", ""))
	_review_tags_label.text = _format_preview_tags(_build_preview_tags(_current_request, validation_errors, diff_summary))
	_review_warning_label.text = (
		"\n".join(_review_warnings) if not _review_warnings.is_empty() else ""
	)
	_risk_label.text = "风险级别: %s" % str(diff_summary.get("risk_level", "low"))
	_risk_label.modulate = _color_for_risk(str(diff_summary.get("risk_level", "low")))
	_diff_output.text = _format_diff_preview(diff_summary)
	_render_prompt_debug()


func _validate_draft(draft: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if str(draft.get("record_type", "")).strip_edges().to_lower() != data_type:
		errors.append("record_type 与当前编辑器类型不一致")
	var operation := str(draft.get("operation", "")).strip_edges()
	if operation != "create" and operation != "revise":
		errors.append("operation 必须是 create 或 revise")
	if not (draft.get("warnings", []) is Array):
		errors.append("warnings 必须是数组")
	var record: Variant = draft.get("record", {})
	if not (record is Dictionary):
		errors.append("record 必须是对象")
		return errors
	if (record as Dictionary).is_empty():
		errors.append("record 不能为空对象")
		return errors
	if _adapter != null:
		errors.append_array(_adapter.validate_draft(draft))
	return errors


func _summarize_diff(request: Dictionary, draft: Dictionary) -> Dictionary:
	var before_record: Dictionary = request.get("current_record", {})
	if str(request.get("mode", "create")) == "create":
		before_record = {}
	var after_record: Dictionary = draft.get("record", {})
	if _adapter != null and _adapter.has_method("summarize_record_changes"):
		return _adapter.summarize_record_changes(before_record, after_record)
	return {
		"summary_lines": [],
		"added_paths": [],
		"changed_paths": [],
		"removed_paths": [],
		"risk_level": "low"
	}


func _build_review_warnings(request: Dictionary, current_diff_summary: Dictionary) -> Array[String]:
	var warnings: Array[String] = []
	if _has_empty_record(_current_draft):
		warnings.append("AI 返回了空 record，已禁止应用。")

	var mode := str(request.get("mode", "create"))
	if mode == "revise" and _looks_like_minimal_change_request(request):
		var total_changes := _count_total_changes(current_diff_summary)
		if total_changes >= 8 or str(current_diff_summary.get("risk_level", "low")) == "high":
			warnings.append("当前是调整模式，但草稿改动范围较大，请重点检查未在提示词中提到的字段。")
	return warnings


func _looks_like_minimal_change_request(request: Dictionary) -> bool:
	var prompt_text := "%s %s" % [
		str(request.get("user_prompt", "")),
		str(request.get("adjustment_prompt", ""))
	]
	prompt_text = prompt_text.to_lower()
	for token in ["微调", "润色", "小改", "只改", "minor", "small", "tweak", "polish", "refine"]:
		if prompt_text.contains(token):
			return true
	return prompt_text.length() <= 24


func _count_total_changes(current_diff_summary: Dictionary) -> int:
	return (
		(current_diff_summary.get("added_paths", []) as Array).size()
		+ (current_diff_summary.get("changed_paths", []) as Array).size()
		+ (current_diff_summary.get("removed_paths", []) as Array).size()
	)


func _build_preview_tags(
	request: Dictionary,
	current_validation_errors: Array[String],
	current_diff_summary: Dictionary
) -> Array[String]:
	var tags: Array[String] = []
	if str(request.get("mode", "create")) == "create":
		for error in current_validation_errors:
			if error.contains("不能复用已有") or error.contains("已存在"):
				tags.append("目标 ID 冲突")
				break
		for error in current_validation_errors:
			if error.contains("不存在") or error.contains("未知"):
				tags.append("引用未知")
				break
		if _has_reference_changes(current_diff_summary):
			tags.append("包含引用变更")
	if str(current_diff_summary.get("risk_level", "low")) == "high":
		tags.append("高风险")
	if not provider_error.is_empty():
		tags.append("Provider Error")
	if _has_empty_record(_current_draft):
		tags.append("空草稿")
	return tags


func _has_reference_changes(current_diff_summary: Dictionary) -> bool:
	for key in ["added_paths", "changed_paths", "removed_paths"]:
		for path_variant in current_diff_summary.get(key, []):
			var path := str(path_variant)
			if path.contains("dialog_id") or path.contains("item_id") or path.contains("target") or path.contains("skill") or path.contains("recipe") or path.contains("effect"):
				return true
	return false


func _format_preview_tags(tags: Array[String]) -> String:
	if tags.is_empty():
		return "预览标签: 无"
	return "预览标签: %s" % " | ".join(tags)


func _format_diff_preview(current_diff_summary: Dictionary) -> String:
	if current_diff_summary.is_empty():
		return "暂无差异信息"

	var lines: Array[String] = []
	lines.append("Summary")
	for summary_line in current_diff_summary.get("summary_lines", []):
		lines.append("- %s" % str(summary_line))
	lines.append("")
	lines.append("新增字段")
	lines.append_array(_format_path_lines(current_diff_summary.get("added_paths", [])))
	lines.append("")
	lines.append("修改字段")
	lines.append_array(_format_path_lines(current_diff_summary.get("changed_paths", [])))
	lines.append("")
	lines.append("删除字段")
	lines.append_array(_format_path_lines(current_diff_summary.get("removed_paths", [])))
	return "\n".join(lines)


func _format_path_lines(paths: Array) -> Array[String]:
	if paths.is_empty():
		return ["- 无"]
	var result: Array[String] = []
	for path_variant in paths:
		result.append("- %s" % str(path_variant))
	return result


func _collect_validation_lines() -> Array[String]:
	var lines: Array[String] = []
	for raw_line in _validation_output.text.split("\n", false):
		var line := raw_line.strip_edges()
		if not line.is_empty() and line != "校验通过":
			lines.append(line)
	return lines


func _render_prompt_debug() -> void:
	var debug_payload := {
		"request_meta": last_request_meta,
		"validation_errors": validation_errors,
		"provider_error": provider_error,
		"diff_summary": diff_summary
	}
	_prompt_debug_output.text = JSON.stringify(debug_payload, "\t")
	_prompt_debug_output.visible = _prompt_debug_toggle.button_pressed


func _on_apply_pressed() -> void:
	if _current_draft.is_empty() or _adapter == null:
		return
	var applied: bool = _adapter.apply_draft(_current_draft)
	if applied:
		_set_status("草稿已应用到编辑器，仍需手动保存")
		hide()
	else:
		_set_status("应用草稿失败，当前草稿已保留")


func _on_copy_pressed() -> void:
	if _current_draft.is_empty():
		return
	DisplayServer.clipboard_set(JSON.stringify(_current_draft.get("record", {}), "\t"))
	_set_status("已复制 record JSON")


func _on_discard_pressed() -> void:
	_current_draft.clear()
	_current_request.clear()
	last_request_meta.clear()
	diff_summary.clear()
	validation_errors.clear()
	provider_error = ""
	_review_warnings.clear()
	_summary_output.text = ""
	_record_json_output.text = ""
	_validation_output.text = ""
	_raw_output.text = ""
	_current_snapshot_output.text = ""
	_draft_snapshot_output.text = ""
	_diff_output.text = ""
	_review_tags_label.text = "预览标签: 无"
	_review_warning_label.text = ""
	_risk_label.text = "风险级别: -"
	_risk_label.modulate = Color(1, 1, 1)
	_render_prompt_debug()
	_refresh_action_buttons()
	_set_status("已丢弃当前草稿")


func _on_prompt_debug_toggled(button_pressed: bool) -> void:
	_prompt_debug_output.visible = button_pressed


func _normalize_provider_error(provider_result: Dictionary) -> String:
	var status_code := int(provider_result.get("status_code", 0))
	var error_text := str(provider_result.get("error", "AI 生成失败")).strip_edges()
	if status_code == 401 or error_text.contains("鉴权"):
		return "鉴权失败: %s" % error_text
	if status_code == 429 or error_text.contains("频繁"):
		return "限流: %s" % error_text
	if status_code >= 500 or error_text.contains("服务"):
		return "服务错误: %s" % error_text
	if error_text.contains("JSON"):
		return "输出 JSON 非法: %s" % error_text
	if error_text.contains("网络") or error_text.contains("初始化失败") or status_code == 0:
		return "网络失败: %s" % error_text
	return error_text


func _has_empty_record(draft: Dictionary) -> bool:
	var record := draft.get("record", {})
	return record is Dictionary and (record as Dictionary).is_empty()


func _color_for_risk(risk_level: String) -> Color:
	match risk_level:
		"high":
			return Color(0.95, 0.45, 0.4)
		"medium":
			return Color(0.95, 0.8, 0.35)
		_:
			return Color(0.65, 0.9, 0.65)


func _make_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label


func _make_wrap_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _make_readonly_text_edit(height: int) -> TextEdit:
	var text_edit := TextEdit.new()
	text_edit.custom_minimum_size = Vector2(0, height)
	text_edit.editable = false
	text_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return text_edit


func _set_status(message: String) -> void:
	if _status_label:
		_status_label.text = message
