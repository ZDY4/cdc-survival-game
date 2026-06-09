extends Node

const BUS_NAME := "SFX"
const MUSIC_BUS_NAME := "Music"
const MASTER_BUS_NAME := "Master"
const SAMPLE_RATE := 44100.0
const MAX_RECENT_EVENTS := 12
const PLAYER_POOL_SIZE := 4
const SPATIAL_PLAYER_POOL_SIZE := 3
const FALLBACK_SOUND_ID := "event_fallback"

const SPATIAL_EVENT_KINDS := {
	"pickup_granted": true,
	"container_opened": true,
	"container_closed": true,
	"container_transferred": true,
	"door_toggled": true,
	"door_unlocked": true,
	"door_auto_opened": true,
	"attack_resolved": true,
	"weapon_reloaded": true,
	"ammo_consumed": true,
	"actor_defeated": true,
	"corpse_created": true,
}

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
var _spatial_players: Array[AudioStreamPlayer3D] = []
var _next_player_index := 0
var _next_spatial_player_index := 0
var _music_player: AudioStreamPlayer
var _ambience_player: AudioStreamPlayer
var _music_phase := 0.0
var _ambience_phase := 0.0
var _music_snapshot: Dictionary = {}
var _ambience_snapshot: Dictionary = {}
var _spatial_snapshot: Dictionary = {}
var _spatial_event_sequence := 0
var _settings_snapshot: Dictionary = {}
var _music_start_count := 0
var _ambience_start_count := 0
var _spatial_triggered_count := 0
var _spatial_played_count := 0
var _spatial_skipped_headless_count := 0


func _ready() -> void:
	_ensure_players()
	_ensure_layer_players()


func _process(_delta: float) -> void:
	if DisplayServer.get_name() == "headless" or not placeholder_enabled:
		return
	_music_phase = _fill_looping_player(_music_player, 132.0, 0.035, _music_phase)
	_ambience_phase = _fill_looping_player(_ambience_player, 72.0, 0.025, _ambience_phase)


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
	_music_start_count = 0
	_ambience_start_count = 0
	_music_phase = 0.0
	_ambience_phase = 0.0
	_spatial_triggered_count = 0
	_spatial_played_count = 0
	_spatial_skipped_headless_count = 0
	_spatial_event_sequence = 0
	_spatial_snapshot.clear()


func configure_runtime_audio(runtime_snapshot: Dictionary, world_snapshot: Dictionary = {}) -> Dictionary:
	var map_data: Dictionary = _dictionary_or_empty(world_snapshot.get("map", {}))
	if map_data.is_empty():
		map_data = _dictionary_or_empty(runtime_snapshot.get("map", {}))
	var map_id := str(map_data.get("id", runtime_snapshot.get("active_map_id", "default"))).strip_edges()
	if map_id.is_empty():
		map_id = "default"
	_start_music_placeholder("placeholder_music:%s" % map_id)
	_start_ambience_placeholder("placeholder_ambience:%s" % map_id, map_id)
	return snapshot()


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
		_process_spatial_runtime_event(event_data, runtime_snapshot)
	last_event_index = events.size()


func play_ui_feedback(event_kind: String, payload: Dictionary = {}) -> Dictionary:
	var event_payload := payload.duplicate(true)
	event_payload["audio_source"] = str(event_payload.get("audio_source", "ui"))
	_process_event({
		"kind": event_kind,
		"payload": event_payload,
	}, -1)
	return snapshot()


func play_spatial_feedback(event_kind: String, payload: Dictionary = {}, position: Vector3 = Vector3.ZERO) -> Dictionary:
	var event_payload := payload.duplicate(true)
	event_payload["audio_source"] = str(event_payload.get("audio_source", "world_spatial"))
	event_payload["spatial"] = true
	event_payload["spatial_source"] = str(event_payload.get("spatial_source", "manual"))
	_process_event({
		"kind": event_kind,
		"payload": event_payload,
	}, -1)
	_play_spatial_placeholder_sound(_sound_id_for_event(event_kind, event_payload), position, event_kind, event_payload)
	return snapshot()


func apply_settings_snapshot(settings: Dictionary = {}) -> Dictionary:
	_settings_snapshot = settings.duplicate(true)
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
		"buses": _bus_snapshot(),
		"mix_layers": _mix_layer_snapshot(),
		"music": _music_snapshot.duplicate(true),
		"ambience": _ambience_snapshot.duplicate(true),
		"spatial": _spatial_snapshot.duplicate(true) if not _spatial_snapshot.is_empty() else _default_spatial_snapshot(),
		"settings": _settings_snapshot.duplicate(true),
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
		"spatial_source": str(payload.get("spatial_source", "")),
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
		"location_id": str(payload.get("location_id", "")),
		"map_id": str(payload.get("map_id", "")),
		"quest_id": str(payload.get("quest_id", "")),
		"quest_state": str(payload.get("quest_state", "")),
		"recipe_id": str(payload.get("recipe_id", "")),
		"category_id": str(payload.get("category_id", "")),
		"item_id": str(payload.get("item_id", "")),
		"slot_id": str(payload.get("slot_id", "")),
		"group_id": str(payload.get("group_id", "")),
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
		"observe_mode": bool(payload.get("observe_mode", false)),
		"observe_playback": bool(payload.get("observe_playback", false)),
		"auto_tick": bool(payload.get("auto_tick", false)),
		"observe_speed": str(payload.get("observe_speed", "")),
		"stack_index": int(payload.get("stack_index", 0)),
		"cart_count": int(payload.get("cart_count", 0)),
		"queue_count": int(payload.get("queue_count", 0)),
		"unit_price": int(payload.get("unit_price", 0)),
		"total_price": int(payload.get("total_price", 0)),
		"value": payload.get("value", null),
	}
	if payload.has("spatial_position"):
		entry["spatial_position"] = _dictionary_or_empty(payload.get("spatial_position", {})).duplicate(true)
	recent_events.append(entry)
	while recent_events.size() > MAX_RECENT_EVENTS:
		recent_events.pop_front()
	if not bool(payload.get("spatial", false)):
		_play_placeholder_sound(sound_id)


func _process_spatial_runtime_event(event_data: Dictionary, runtime_snapshot: Dictionary) -> void:
	var event_kind := str(event_data.get("kind", "")).strip_edges()
	if event_kind.is_empty() or not SPATIAL_EVENT_KINDS.has(event_kind):
		return
	var payload: Dictionary = _dictionary_or_empty(event_data.get("payload", {}))
	if str(payload.get("audio_source", "simulation")) == "ui":
		return
	var position_result: Dictionary = _spatial_position_for_event(event_kind, payload, runtime_snapshot)
	if not bool(position_result.get("success", false)):
		return
	var spatial_payload := payload.duplicate(true)
	spatial_payload["audio_source"] = "simulation_spatial"
	spatial_payload["spatial"] = true
	spatial_payload["spatial_source"] = str(position_result.get("source", "runtime_snapshot"))
	spatial_payload["spatial_grid"] = _dictionary_or_empty(position_result.get("grid", {})).duplicate(true)
	spatial_payload["spatial_position"] = _dictionary_or_empty(position_result.get("position", {})).duplicate(true)
	_spatial_event_sequence += 1
	spatial_payload["spatial_event_sequence"] = _spatial_event_sequence
	var sound_id := _sound_id_for_event(event_kind, spatial_payload)
	if sound_id.is_empty():
		return
	_play_spatial_placeholder_sound(sound_id, _vector3_from_snapshot(_dictionary_or_empty(position_result.get("position", {}))), event_kind, spatial_payload)


func _spatial_position_for_event(event_kind: String, payload: Dictionary, runtime_snapshot: Dictionary) -> Dictionary:
	var actors_by_id := _actors_by_id(runtime_snapshot)
	var grid := _event_grid(payload, actors_by_id)
	if grid.is_empty():
		return {"success": false, "reason": "spatial_grid_missing", "event_kind": event_kind}
	var position := _grid_to_world_position(grid)
	return {
		"success": true,
		"event_kind": event_kind,
		"source": str(grid.get("spatial_source", "payload_or_actor_grid")),
		"grid": grid,
		"position": _vector3_snapshot(position),
	}


func _event_grid(payload: Dictionary, actors_by_id: Dictionary) -> Dictionary:
	for key in ["target_grid", "grid_position", "anchor", "grid"]:
		var explicit_grid: Dictionary = _dictionary_or_empty(payload.get(key, {}))
		if not explicit_grid.is_empty():
			var output := explicit_grid.duplicate(true)
			output["spatial_source"] = key
			return output
	for actor_key in ["target_actor_id", "actor_id", "source_actor_id", "defeated_by_actor_id"]:
		var actor_id := int(payload.get(actor_key, 0))
		if actor_id <= 0 or not actors_by_id.has(actor_id):
			continue
		var actor_data: Dictionary = _dictionary_or_empty(actors_by_id.get(actor_id, {}))
		var actor_grid: Dictionary = _dictionary_or_empty(actor_data.get("grid_position", {}))
		if actor_grid.is_empty():
			continue
		var output := actor_grid.duplicate(true)
		output["spatial_source"] = actor_key
		output["spatial_actor_id"] = actor_id
		return output
	return {}


func _actors_by_id(runtime_snapshot: Dictionary) -> Dictionary:
	var output := {}
	for actor_value in _array_or_empty(runtime_snapshot.get("actors", [])):
		var actor_data: Dictionary = _dictionary_or_empty(actor_value)
		var actor_id := int(actor_data.get("actor_id", 0))
		if actor_id > 0:
			output[actor_id] = actor_data
	return output


func _grid_to_world_position(grid: Dictionary) -> Vector3:
	return Vector3(
		float(grid.get("x", 0)),
		float(grid.get("y", 0)) + 0.65,
		float(grid.get("z", 0))
	)


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


func _start_music_placeholder(track_id: String) -> void:
	_ensure_layer_players()
	var already_active := bool(_music_snapshot.get("active", false)) and str(_music_snapshot.get("track_id", "")) == track_id
	_music_snapshot = {
		"enabled": enabled,
		"active": true,
		"placeholder": placeholder_enabled,
		"track_id": track_id,
		"bus": MUSIC_BUS_NAME,
		"bus_index": AudioServer.get_bus_index(MUSIC_BUS_NAME),
		"loop": true,
		"source": "runtime_map",
		"started_count": _music_start_count,
		"headless_skipped": DisplayServer.get_name() == "headless",
	}
	if already_active:
		return
	_music_start_count += 1
	_music_snapshot["started_count"] = _music_start_count
	if DisplayServer.get_name() == "headless" or not placeholder_enabled or _music_player == null:
		return
	_music_player.bus = MUSIC_BUS_NAME
	_music_player.stream = _looping_placeholder_stream(132.0, 0.035)
	_music_player.play()


func _start_ambience_placeholder(ambience_id: String, map_id: String) -> void:
	_ensure_layer_players()
	var already_active := bool(_ambience_snapshot.get("active", false)) and str(_ambience_snapshot.get("ambience_id", "")) == ambience_id
	_ambience_snapshot = {
		"enabled": enabled,
		"active": true,
		"placeholder": placeholder_enabled,
		"ambience_id": ambience_id,
		"map_id": map_id,
		"bus": BUS_NAME,
		"bus_index": AudioServer.get_bus_index(BUS_NAME),
		"loop": true,
		"source": "runtime_map",
		"started_count": _ambience_start_count,
		"headless_skipped": DisplayServer.get_name() == "headless",
	}
	if already_active:
		return
	_ambience_start_count += 1
	_ambience_snapshot["started_count"] = _ambience_start_count
	if DisplayServer.get_name() == "headless" or not placeholder_enabled or _ambience_player == null:
		return
	_ambience_player.bus = BUS_NAME
	_ambience_player.stream = _looping_placeholder_stream(72.0, 0.025)
	_ambience_player.play()


func _play_spatial_placeholder_sound(sound_id: String, position: Vector3, event_kind: String, payload: Dictionary) -> void:
	_spatial_triggered_count += 1
	var resolved_sound_id := sound_id
	if resolved_sound_id.is_empty() or not SOUND_PROFILES.has(resolved_sound_id):
		resolved_sound_id = FALLBACK_SOUND_ID
	_ensure_layer_players()
	_spatial_snapshot = {
		"enabled": enabled,
		"placeholder": placeholder_enabled,
		"bus": BUS_NAME,
		"bus_index": AudioServer.get_bus_index(BUS_NAME),
		"player_pool_size": _spatial_players.size(),
		"triggered_count": _spatial_triggered_count,
		"played_count": _spatial_played_count,
		"skipped_headless_count": _spatial_skipped_headless_count,
		"last_event_kind": event_kind,
		"last_sound_id": resolved_sound_id,
		"last_position": _vector3_snapshot(position),
		"attenuation_model": "inverse_distance",
		"unit_size": 2.0,
		"audio_source": str(payload.get("audio_source", "world_spatial")),
	}
	if DisplayServer.get_name() == "headless" or not placeholder_enabled or _spatial_players.is_empty():
		_spatial_skipped_headless_count += 1
		_spatial_snapshot["skipped_headless_count"] = _spatial_skipped_headless_count
		return
	var player: AudioStreamPlayer3D = _spatial_players[_next_spatial_player_index % _spatial_players.size()]
	_next_spatial_player_index += 1
	player.bus = BUS_NAME
	player.global_position = position
	player.unit_size = 2.0
	player.max_distance = 24.0
	player.stream = _one_shot_placeholder_stream(resolved_sound_id)
	player.play()
	_fill_one_shot_player(player, resolved_sound_id)
	_spatial_played_count += 1
	_spatial_snapshot["played_count"] = _spatial_played_count


func _ensure_players() -> void:
	if not _players.is_empty():
		return
	for index in range(PLAYER_POOL_SIZE):
		var player := AudioStreamPlayer.new()
		player.name = "AudioFeedbackPlayer%d" % (index + 1)
		player.bus = BUS_NAME
		add_child(player)
		_players.append(player)


func _ensure_layer_players() -> void:
	if _music_player == null:
		_music_player = AudioStreamPlayer.new()
		_music_player.name = "MusicPlaceholderPlayer"
		_music_player.bus = MUSIC_BUS_NAME
		add_child(_music_player)
	if _ambience_player == null:
		_ambience_player = AudioStreamPlayer.new()
		_ambience_player.name = "AmbiencePlaceholderPlayer"
		_ambience_player.bus = BUS_NAME
		add_child(_ambience_player)
	if _spatial_players.is_empty():
		for index in range(SPATIAL_PLAYER_POOL_SIZE):
			var player := AudioStreamPlayer3D.new()
			player.name = "SpatialAudioPlaceholderPlayer%d" % (index + 1)
			player.bus = BUS_NAME
			player.unit_size = 2.0
			player.max_distance = 24.0
			add_child(player)
			_spatial_players.append(player)


func _looping_placeholder_stream(frequency: float, volume: float) -> AudioStreamGenerator:
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = SAMPLE_RATE
	stream.buffer_length = 0.5
	stream.set_meta("placeholder_frequency", frequency)
	stream.set_meta("placeholder_volume", volume)
	return stream


func _one_shot_placeholder_stream(sound_id: String) -> AudioStreamGenerator:
	var profile: Dictionary = _dictionary_or_empty(SOUND_PROFILES.get(sound_id, SOUND_PROFILES[FALLBACK_SOUND_ID]))
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = SAMPLE_RATE
	stream.buffer_length = clampf(float(profile.get("duration", 0.06)), 0.02, 0.30) + 0.05
	return stream


func _fill_looping_player(player: AudioStreamPlayer, frequency: float, volume: float, phase: float) -> float:
	if player == null or not player.playing:
		return phase
	var playback := player.get_stream_playback() as AudioStreamGeneratorPlayback
	if playback == null:
		return phase
	var frames: int = mini(2048, playback.get_frames_available())
	for _frame_index in range(frames):
		var sample: float = sin(phase) * volume
		playback.push_frame(Vector2(sample, sample))
		phase = fmod(phase + TAU * frequency / SAMPLE_RATE, TAU)
	return phase


func _fill_one_shot_player(player: AudioStreamPlayer3D, sound_id: String) -> void:
	var playback := player.get_stream_playback() as AudioStreamGeneratorPlayback
	if playback == null:
		playback_failure_count += 1
		return
	var profile: Dictionary = _dictionary_or_empty(SOUND_PROFILES.get(sound_id, SOUND_PROFILES[FALLBACK_SOUND_ID]))
	var frequency := maxf(20.0, float(profile.get("frequency", 440.0)))
	var duration := clampf(float(profile.get("duration", 0.06)), 0.02, 0.30)
	var volume := clampf(float(profile.get("volume", 0.10)), 0.0, 0.40)
	var frame_count := int(duration * SAMPLE_RATE)
	for frame_index in range(frame_count):
		var progress := float(frame_index) / maxf(1.0, float(frame_count - 1))
		var envelope := 1.0 - progress
		var sample := sin(TAU * frequency * (float(frame_index) / SAMPLE_RATE)) * volume * envelope
		playback.push_frame(Vector2(sample, sample))


func _bus_snapshot() -> Dictionary:
	var result := {}
	for bus_name in [MASTER_BUS_NAME, MUSIC_BUS_NAME, BUS_NAME]:
		var bus_index := AudioServer.get_bus_index(bus_name)
		result[bus_name] = {
			"exists": bus_index >= 0,
			"index": bus_index,
			"volume_db": AudioServer.get_bus_volume_db(bus_index) if bus_index >= 0 else 0.0,
			"muted": AudioServer.is_bus_mute(bus_index) if bus_index >= 0 else false,
		}
	return result


func _mix_layer_snapshot() -> Dictionary:
	return {
		"ui": {"bus": BUS_NAME, "placeholder": placeholder_enabled, "source": "ui_controls"},
		"sfx": {"bus": BUS_NAME, "placeholder": placeholder_enabled, "source": "simulation_events"},
		"music": {"bus": MUSIC_BUS_NAME, "placeholder": placeholder_enabled, "source": "runtime_map"},
		"ambience": {"bus": BUS_NAME, "placeholder": placeholder_enabled, "source": "runtime_map"},
		"spatial": {"bus": BUS_NAME, "placeholder": placeholder_enabled, "source": "world_positions"},
	}


func _default_spatial_snapshot() -> Dictionary:
	return {
		"enabled": enabled,
		"placeholder": placeholder_enabled,
		"bus": BUS_NAME,
		"bus_index": AudioServer.get_bus_index(BUS_NAME),
		"player_pool_size": _spatial_players.size(),
		"triggered_count": _spatial_triggered_count,
		"played_count": _spatial_played_count,
		"skipped_headless_count": _spatial_skipped_headless_count,
		"active": false,
		"attenuation_model": "inverse_distance",
		"unit_size": 2.0,
	}


func _vector3_snapshot(value: Vector3) -> Dictionary:
	return {
		"x": value.x,
		"y": value.y,
		"z": value.z,
	}


func _vector3_from_snapshot(value: Dictionary) -> Vector3:
	return Vector3(
		float(value.get("x", 0.0)),
		float(value.get("y", 0.0)),
		float(value.get("z", 0.0))
	)


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
