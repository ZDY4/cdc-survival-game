extends Node

const BUS_NAME := "SFX"
const SAMPLE_RATE := 44100.0
const MAX_RECENT_EVENTS := 12
const PLAYER_POOL_SIZE := 4
const FALLBACK_SOUND_ID := "event_fallback"

const EVENT_SOUND_MAP := {
	"pickup_granted": "pickup",
	"container_opened": "container_open",
	"container_closed": "container_close",
	"container_transferred": "item_transfer",
	"inventory_item_dropped": "item_drop",
	"trade_confirmed": "trade_confirm",
	"trade_closed": "ui_click",
	"recipe_crafted": "craft",
	"skill_used": "skill",
	"quest_advanced": "quest_update",
	"quest_completed": "quest_complete",
	"door_toggled": "door_toggle",
	"door_unlocked": "door_unlock",
	"door_auto_opened": "door_toggle",
	"attack_resolved": "attack",
	"weapon_reloaded": "weapon_reload",
	"ammo_consumed": "ammo_consume",
	"actor_defeated": "death",
	"corpse_created": "death",
	"combat_started": "combat_start",
	"combat_ended": "combat_end",
	"stage_panel_opened": "ui_panel_open",
	"stage_panel_closed": "ui_panel_close",
	"settings_panel_opened": "ui_panel_open",
	"settings_panel_closed": "ui_panel_close",
	"ui_button_pressed": "ui_click",
	"ui_slider_changed": "ui_slider",
	"ui_option_selected": "ui_select",
	"ui_toggle_changed": "ui_toggle",
	"player_command_rejected": "error",
	"ui_feedback": "ui_feedback",
	"audio_missing_asset_probe": "missing_audio_asset",
}

const SOUND_PROFILES := {
	"ui_click": {"frequency": 620.0, "duration": 0.045, "volume": 0.10},
	"ui_slider": {"frequency": 580.0, "duration": 0.035, "volume": 0.08},
	"ui_select": {"frequency": 700.0, "duration": 0.050, "volume": 0.10},
	"ui_toggle": {"frequency": 500.0, "duration": 0.055, "volume": 0.10},
	"ui_panel_open": {"frequency": 660.0, "duration": 0.055, "volume": 0.10},
	"ui_panel_close": {"frequency": 420.0, "duration": 0.050, "volume": 0.09},
	"ui_feedback": {"frequency": 520.0, "duration": 0.05, "volume": 0.10},
	"error": {"frequency": 180.0, "duration": 0.11, "volume": 0.14},
	"pickup": {"frequency": 760.0, "duration": 0.07, "volume": 0.12},
	"item_transfer": {"frequency": 680.0, "duration": 0.055, "volume": 0.11},
	"container_open": {"frequency": 320.0, "duration": 0.10, "volume": 0.13},
	"container_close": {"frequency": 240.0, "duration": 0.08, "volume": 0.11},
	"item_drop": {"frequency": 360.0, "duration": 0.06, "volume": 0.11},
	"trade_confirm": {"frequency": 880.0, "duration": 0.08, "volume": 0.12},
	"craft": {"frequency": 540.0, "duration": 0.12, "volume": 0.13},
	"skill": {"frequency": 700.0, "duration": 0.12, "volume": 0.12},
	"quest_update": {"frequency": 840.0, "duration": 0.10, "volume": 0.12},
	"quest_complete": {"frequency": 980.0, "duration": 0.16, "volume": 0.14},
	"door_toggle": {"frequency": 260.0, "duration": 0.12, "volume": 0.13},
	"door_open": {"frequency": 300.0, "duration": 0.12, "volume": 0.13},
	"door_close": {"frequency": 210.0, "duration": 0.11, "volume": 0.12},
	"door_auto_open": {"frequency": 340.0, "duration": 0.09, "volume": 0.11},
	"door_unlock": {"frequency": 470.0, "duration": 0.11, "volume": 0.12},
	"combat_start": {"frequency": 220.0, "duration": 0.13, "volume": 0.14},
	"combat_end": {"frequency": 360.0, "duration": 0.10, "volume": 0.11},
	"attack": {"frequency": 300.0, "duration": 0.07, "volume": 0.14},
	"attack_melee": {"frequency": 280.0, "duration": 0.075, "volume": 0.13},
	"attack_ranged": {"frequency": 720.0, "duration": 0.045, "volume": 0.15},
	"hit": {"frequency": 190.0, "duration": 0.09, "volume": 0.15},
	"hit_ranged": {"frequency": 230.0, "duration": 0.075, "volume": 0.15},
	"weapon_reload": {"frequency": 520.0, "duration": 0.13, "volume": 0.12},
	"ammo_consume": {"frequency": 780.0, "duration": 0.035, "volume": 0.08},
	"death": {"frequency": 120.0, "duration": 0.18, "volume": 0.15},
	"event_fallback": {"frequency": 440.0, "duration": 0.055, "volume": 0.08},
}

var enabled := true
var placeholder_enabled := true
var last_event_index := 0
var event_sequence := 0
var triggered_count := 0
var played_count := 0
var fallback_count := 0
var skipped_headless_count := 0
var playback_failure_count := 0
var last_sound_id := ""
var last_event_kind := ""
var recent_events: Array[Dictionary] = []
var _players: Array[AudioStreamPlayer] = []
var _next_player_index := 0


func _ready() -> void:
	_ensure_players()


func reset() -> void:
	last_event_index = 0
	event_sequence = 0
	triggered_count = 0
	played_count = 0
	fallback_count = 0
	skipped_headless_count = 0
	playback_failure_count = 0
	last_sound_id = ""
	last_event_kind = ""
	recent_events.clear()


func process_runtime_snapshot(runtime_snapshot: Dictionary) -> void:
	if not enabled:
		return
	var events := _array_or_empty(runtime_snapshot.get("events", []))
	if events.size() < last_event_index:
		last_event_index = 0
	for index in range(last_event_index, events.size()):
		var event_data: Dictionary = _dictionary_or_empty(events[index])
		if event_data.is_empty():
			continue
		_process_event(event_data, index)
	last_event_index = events.size()


func play_ui_feedback(event_kind: String, payload: Dictionary = {}) -> Dictionary:
	var event_payload := payload.duplicate(true)
	event_payload["audio_source"] = str(event_payload.get("audio_source", "ui"))
	_process_event({
		"kind": event_kind,
		"payload": event_payload,
	}, -1)
	return snapshot()


func snapshot() -> Dictionary:
	return {
		"enabled": enabled,
		"placeholder_enabled": placeholder_enabled,
		"bus": BUS_NAME,
		"bus_index": AudioServer.get_bus_index(BUS_NAME),
		"event_index": last_event_index,
		"event_sequence": event_sequence,
		"triggered_count": triggered_count,
		"played_count": played_count,
		"fallback_count": fallback_count,
		"skipped_headless_count": skipped_headless_count,
		"playback_failure_count": playback_failure_count,
		"last_sound_id": last_sound_id,
		"last_event_kind": last_event_kind,
		"mapped_event_count": EVENT_SOUND_MAP.size(),
		"sound_profile_count": SOUND_PROFILES.size(),
		"fallback_sound_id": FALLBACK_SOUND_ID,
		"recent_events": recent_events.duplicate(true),
	}


func _process_event(event_data: Dictionary, event_index: int) -> void:
	var event_kind := str(event_data.get("kind", "")).strip_edges()
	if event_kind.is_empty():
		return
	var payload: Dictionary = _dictionary_or_empty(event_data.get("payload", {}))
	var sound_id := _sound_id_for_event(event_kind, payload)
	if sound_id.is_empty():
		return
	var used_fallback := sound_id == FALLBACK_SOUND_ID or not SOUND_PROFILES.has(sound_id)
	if used_fallback:
		sound_id = FALLBACK_SOUND_ID
		fallback_count += 1
	event_sequence += 1
	triggered_count += 1
	last_sound_id = sound_id
	last_event_kind = event_kind
	var entry := {
		"sequence": event_sequence,
		"event_index": event_index,
		"event_kind": event_kind,
		"sound_id": sound_id,
		"fallback": used_fallback,
		"bus": BUS_NAME,
		"placeholder": placeholder_enabled,
		"audio_source": str(payload.get("audio_source", "simulation")),
		"panel_id": str(payload.get("panel_id", "")),
		"action": str(payload.get("action", "")),
		"reason": str(payload.get("reason", "")),
		"control_name": str(payload.get("control_name", "")),
		"control_kind": str(payload.get("control_kind", "")),
		"setting_key": str(payload.get("setting_key", "")),
		"skill_id": str(payload.get("skill_id", "")),
		"attribute_id": str(payload.get("attribute_id", "")),
		"dialogue_id": str(payload.get("dialogue_id", "")),
		"node_id": str(payload.get("node_id", "")),
		"option_id": str(payload.get("option_id", "")),
		"quest_id": str(payload.get("quest_id", "")),
		"quest_state": str(payload.get("quest_state", "")),
		"recipe_id": str(payload.get("recipe_id", "")),
		"category_id": str(payload.get("category_id", "")),
		"item_id": str(payload.get("item_id", "")),
		"slot_id": str(payload.get("slot_id", "")),
		"filter_id": str(payload.get("filter_id", "")),
		"sort_id": str(payload.get("sort_id", "")),
		"tree_id": str(payload.get("tree_id", "")),
		"source": str(payload.get("source", "")),
		"target_source": str(payload.get("target_source", "")),
		"count": int(payload.get("count", 0)),
		"ammo_count": int(payload.get("ammo_count", 0)),
		"option_index": int(payload.get("option_index", 0)),
		"target_actor_id": int(payload.get("target_actor_id", 0)),
		"target_definition_id": str(payload.get("target_definition_id", "")),
		"stack_index": int(payload.get("stack_index", 0)),
		"cart_count": int(payload.get("cart_count", 0)),
		"queue_count": int(payload.get("queue_count", 0)),
		"unit_price": int(payload.get("unit_price", 0)),
		"total_price": int(payload.get("total_price", 0)),
		"value": payload.get("value", null),
	}
	recent_events.append(entry)
	while recent_events.size() > MAX_RECENT_EVENTS:
		recent_events.pop_front()
	_play_placeholder_sound(sound_id)


func _sound_id_for_event(event_kind: String, payload: Dictionary) -> String:
	match event_kind:
		"attack_resolved":
			return _attack_sound_id(payload)
		"door_toggled":
			return "door_open" if bool(payload.get("is_open", false)) else "door_close"
		"door_auto_opened":
			return "door_auto_open"
	if EVENT_SOUND_MAP.has(event_kind):
		return str(EVENT_SOUND_MAP[event_kind])
	return ""


func _attack_sound_id(payload: Dictionary) -> String:
	var ranged := int(payload.get("range", 1)) > 1
	if _event_damage_value(payload) > 0.0:
		return "hit_ranged" if ranged else "hit"
	return "attack_ranged" if ranged else "attack_melee"


func _event_damage_value(payload: Dictionary) -> float:
	for key in ["damage_dealt", "damage", "final_damage", "hp_damage"]:
		if payload.has(key):
			return maxf(0.0, float(payload.get(key, 0.0)))
	return 0.0


func _play_placeholder_sound(sound_id: String) -> void:
	if not placeholder_enabled:
		return
	if DisplayServer.get_name() == "headless":
		skipped_headless_count += 1
		return
	_ensure_players()
	if _players.is_empty():
		playback_failure_count += 1
		return
	var profile: Dictionary = _dictionary_or_empty(SOUND_PROFILES.get(sound_id, SOUND_PROFILES[FALLBACK_SOUND_ID]))
	var frequency := maxf(20.0, float(profile.get("frequency", 440.0)))
	var duration := clampf(float(profile.get("duration", 0.06)), 0.02, 0.30)
	var volume := clampf(float(profile.get("volume", 0.10)), 0.0, 0.40)
	var player: AudioStreamPlayer = _players[_next_player_index % _players.size()]
	_next_player_index += 1
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = SAMPLE_RATE
	stream.buffer_length = duration + 0.05
	player.bus = BUS_NAME
	player.stream = stream
	player.play()
	var playback := player.get_stream_playback() as AudioStreamGeneratorPlayback
	if playback == null:
		playback_failure_count += 1
		return
	var frame_count := int(duration * SAMPLE_RATE)
	for frame_index in range(frame_count):
		var progress := float(frame_index) / maxf(1.0, float(frame_count - 1))
		var envelope := 1.0 - progress
		var sample := sin(TAU * frequency * (float(frame_index) / SAMPLE_RATE)) * volume * envelope
		playback.push_frame(Vector2(sample, sample))
	played_count += 1


func _ensure_players() -> void:
	if not _players.is_empty():
		return
	for index in range(PLAYER_POOL_SIZE):
		var player := AudioStreamPlayer.new()
		player.name = "AudioFeedbackPlayer%d" % (index + 1)
		player.bus = BUS_NAME
		add_child(player)
		_players.append(player)


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
