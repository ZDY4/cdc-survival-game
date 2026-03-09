extends Node
## EnemySystem - 3D-only enemy runtime provider

class_name EnemySystem

const MovementComponent = preload("res://systems/movement_component.gd")
const CharacterActorScript = preload("res://systems/character_actor.gd")

signal enemy_spawned(enemy_id: String, enemy_instance: Node3D)
signal enemy_despawned(spawn_id: String)

var enemy_database: Dictionary = {}
var active_enemies: Dictionary = {}  # spawn_id -> Node3D

func _ready() -> void:
	_load_enemy_database()

func _load_enemy_database() -> void:
	var data_manager := get_node_or_null("/root/DataManager")
	if data_manager:
		enemy_database = data_manager.get_data("enemies")
	if enemy_database.is_empty() and EnemyDatabase and EnemyDatabase.has_method("get_all_enemy_ids"):
		for enemy_id in EnemyDatabase.get_all_enemy_ids():
			enemy_database[enemy_id] = EnemyDatabase.get_enemy(enemy_id)

func spawn_actor(role_kind: String, role_id: String, world_pos: Vector3, context: Dictionary = {}) -> Node3D:
	if role_kind.to_lower() != "enemy":
		return null
	if role_id.is_empty():
		return null

	var spawn_id: String = str(context.get("spawn_id", "enemy_%d" % Time.get_ticks_msec()))
	if active_enemies.has(spawn_id):
		var existing: Node3D = active_enemies[spawn_id]
		if existing and is_instance_valid(existing):
			return existing
		active_enemies.erase(spawn_id)

	var enemy_data: Dictionary = enemy_database.get(role_id, {})
	if enemy_data.is_empty():
		push_warning("[EnemySystem] Enemy data not found: %s" % role_id)
		return null

	var actor := CharacterActorScript.new()
	actor.name = "Enemy_%s" % spawn_id
	actor.position = world_pos
	actor.set_placeholder_colors(Color(1.0, 0.75, 0.75, 1.0), Color(0.80, 0.25, 0.25, 1.0))
	actor.collision_layer = 1 << 2
	actor.collision_mask = 1
	actor.set_meta("enemy_id", role_id)
	actor.set_meta("role_kind", "enemy")
	actor.set_meta("spawn_id", spawn_id)
	actor.set_meta("enemy_data", enemy_data.duplicate(true))
	actor.add_to_group("enemy")

	var collision_shape := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.42
	shape.height = 1.0
	collision_shape.shape = shape
	collision_shape.position = Vector3(0.0, 1.0, 0.0)
	actor.add_child(collision_shape)

	var name_label := Label3D.new()
	name_label.text = str(enemy_data.get("name", role_id))
	name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_label.font_size = 28
	name_label.position = Vector3(0.0, 2.2, 0.0)
	actor.add_child(name_label)

	var movement_component := MovementComponent.new()
	actor.add_child(movement_component)
	if GridMovementSystem and GridMovementSystem.grid_world:
		movement_component.initialize(actor, GridMovementSystem.grid_world)

	active_enemies[spawn_id] = actor
	enemy_spawned.emit(role_id, actor)
	return actor

func despawn_actor(spawn_id: String) -> void:
	if not active_enemies.has(spawn_id):
		return

	var actor: Node3D = active_enemies[spawn_id]
	active_enemies.erase(spawn_id)
	if actor and is_instance_valid(actor):
		actor.queue_free()
	enemy_despawned.emit(spawn_id)
