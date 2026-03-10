extends Interactable
## Thin wrapper that configures a PickupInteractionOption on Interactable.

const PickupInteractionOption = preload("res://modules/interaction/options/pickup_interaction_option.gd")

# 2. Exports
@export var item_id: String = ""
@export var min_count: int = 1
@export var max_count: int = 1
@export var remove_after_pickup: bool = true
func _ready() -> void:
	super()
	_apply_pickup_option()

func _apply_pickup_option() -> void:
	var pickup_option := PickupInteractionOption.new()
	pickup_option.item_id = item_id
	pickup_option.min_count = min_count
	pickup_option.max_count = max_count
	pickup_option.remove_target_after_pickup = remove_after_pickup
	set_options([pickup_option])
