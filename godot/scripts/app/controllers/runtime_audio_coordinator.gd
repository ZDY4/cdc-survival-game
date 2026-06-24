extends RefCounted

const AudioFeedbackController = preload("res://scripts/app/audio_feedback_controller.gd")

var host


func configure(p_host) -> void:
	host = p_host


func setup_audio_feedback_controller() -> void:
	if host.audio_feedback_controller != null:
		return
	host.audio_feedback_controller = AudioFeedbackController.new()
	host.audio_feedback_controller.name = "AudioFeedbackController"
	host.add_child(host.audio_feedback_controller)


func configure_runtime_audio_layers() -> void:
	if host.audio_feedback_controller == null or host.simulation == null:
		return
	if host.audio_feedback_controller.has_method("configure_runtime_audio"):
		host.audio_feedback_controller.call("configure_runtime_audio", host.simulation.world_runtime_view(), host.world_result)


func process_audio_feedback() -> void:
	if host.audio_feedback_controller == null or host.simulation == null:
		return
	if host.audio_feedback_controller.has_method("process_runtime_snapshot"):
		host.audio_feedback_controller.call("process_runtime_snapshot", host.simulation.world_runtime_view())


func play_ui_audio_feedback(event_kind: String, payload: Dictionary = {}) -> Dictionary:
	if host.audio_feedback_controller == null or not host.audio_feedback_controller.has_method("play_ui_feedback"):
		return {"enabled": false, "reason": "audio_feedback_missing"}
	return dictionary_or_empty(host.audio_feedback_controller.call("play_ui_feedback", event_kind, payload))


func play_spatial_audio_feedback(event_kind: String, payload: Dictionary = {}, position: Vector3 = Vector3.ZERO) -> Dictionary:
	if host.audio_feedback_controller == null or not host.audio_feedback_controller.has_method("play_spatial_feedback"):
		return {"enabled": false, "reason": "audio_feedback_missing"}
	return dictionary_or_empty(host.audio_feedback_controller.call("play_spatial_feedback", event_kind, payload, position))


func play_hud_shortcut_audio(event_kind: String, control_name: String, control_kind: String, action: String, extra_payload: Dictionary = {}) -> Dictionary:
	var payload := {
		"audio_source": "ui",
		"panel_id": "hud",
		"control_name": control_name,
		"control_kind": control_kind,
		"action": action,
	}
	for key in extra_payload.keys():
		payload[key] = extra_payload[key]
	return play_ui_audio_feedback(event_kind, payload)


func settings_applied(snapshot: Dictionary = {}) -> void:
	if host.audio_feedback_controller != null and host.audio_feedback_controller.has_method("apply_settings_snapshot"):
		host.audio_feedback_controller.call("apply_settings_snapshot", snapshot)


func dictionary_or_empty(value: Variant) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}
