extends Control

class_name CombatUI

signal attack_pressed()
signal item_pressed()

var _enemy_portrait: TextureRect
var _enemy_hp_bar: ProgressBar
var _player_hp_bar: ProgressBar
var _attack_button: Button
var _item_button: Button
var _combat_log: RichTextLabel

func _ready():
	# Get nodes after scene is fully ready
	call_deferred("_setup_nodes")

func _setup_nodes():
	_enemy_portrait = get_node_or_null("Background/EnemyPortrait")
	_enemy_hp_bar = get_node_or_null("Background/EnemyHPBar")
	_player_hp_bar = get_node_or_null("Background/PlayerHPBar")
	_attack_button = get_node_or_null("Background/ActionButtons/AttackButton")
	_item_button = get_node_or_null("Background/ActionButtons/ItemButton")
	_combat_log = get_node_or_null("Background/CombatLog")
	
	# Connect button signals
	if _attack_button:
		_attack_button.pressed.connect(_on_attack_pressed)
	if _item_button:
		_item_button.pressed.connect(_on_item_pressed)

func show_combat(enemy_data: Dictionary = {}):
	visible = true
	
	# Update enemy info
	if enemy_data.has("portrait") && _enemy_portrait:
		var portrait_texture = load(enemy_data.portrait)
		if portrait_texture:
			_enemy_portrait.texture = portrait_texture
	
	if _enemy_hp_bar:
		_enemy_hp_bar.max_value = enemy_data.get("hp", 50)
		_enemy_hp_bar.value = enemy_data.get("hp", 50)
	if _player_hp_bar:
		_player_hp_bar.max_value = GameState.player_max_hp
		_player_hp_bar.value = GameState.player_hp
	if _combat_log:
		_combat_log.text = "Combat started! You encountered " + enemy_data.get("name", "Enemy") + "!"

func update_enemy_hp(max_hp: float, current: float):
	if _enemy_hp_bar:
		_enemy_hp_bar.max_value = max_hp
		_enemy_hp_bar.value = current
	if _combat_log:
		_combat_log.text += "\nYou dealt damage to the enemy!"

func update_player_hp(max_hp: float, current: float):
	if _player_hp_bar:
		_player_hp_bar.max_value = max_hp
		_player_hp_bar.value = current
	if _combat_log:
		_combat_log.text += "\nYou took damage!"

func hide_combat():
	visible = false

func _on_attack_pressed():
	attack_pressed.emit()

func _on_item_pressed():
	item_pressed.emit()
