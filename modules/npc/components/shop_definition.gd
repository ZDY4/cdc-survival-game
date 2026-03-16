extends Resource
## Serializable shop data used by scene-bound merchants.

class_name ShopDefinition

@export var buy_price_modifier: float = 1.0
@export var sell_price_modifier: float = 1.0
@export var money: int = 0
@export var inventory: Array[Dictionary] = []
