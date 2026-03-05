extends InteractionOption
class_name AttackInteractionOption

@export var enemy_id: String = "enemy"
@export var enemy_name: String = "敌人"
@export var enemy_hp: int = 30
@export var enemy_max_hp: int = 30
@export var enemy_damage: int = 5
@export var custom_enemy_data: Dictionary = {}

func _init() -> void:
	option_id = "attack"
	display_name = "攻击"
	priority = 1000

func execute(interactable: Node) -> void:
	var combat_data := custom_enemy_data.duplicate(true)
	if combat_data.is_empty():
		combat_data = {
			"id": enemy_id,
			"name": enemy_name,
			"hp": enemy_hp,
			"max_hp": enemy_max_hp,
			"damage": enemy_damage
		}
	
	if CombatModule and CombatModule.has_method("start_combat"):
		CombatModule.start_combat(combat_data)
	
	if EventBus:
		EventBus.emit(EventBus.EventType.SCENE_INTERACTION, {
			"type": "attack",
			"target": interactable.name,
			"data": combat_data
		})
