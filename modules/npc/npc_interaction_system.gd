class_name NPCInteractionSystem
extends Node

const InteractionSystem = preload("res://systems/interaction_system.gd")
const NPC_INTERACTION_MASK: int = 1 << 1

var _scene_root: Node = null
var _interaction_system: InteractionSystem = null
var _is_interaction_active: bool = false

func initialize(scene_root: Node, interaction_system: InteractionSystem) -> void:
    _scene_root = scene_root
    _interaction_system = interaction_system

func try_interact(screen_pos: Vector2) -> bool:
    if _is_interaction_active:
        return false
    if not _scene_root or not _interaction_system:
        return false

    var result := _interaction_system.raycast_screen_position(_scene_root, screen_pos, true, NPC_INTERACTION_MASK)
    if result.is_empty():
        return false

    var collider: Node = result.get("collider", null)
    if not collider:
        return false

    var npc_id := _resolve_npc_id(collider)
    if npc_id.is_empty():
        return false

    _is_interaction_active = true
    _run_interaction(npc_id)
    return true

func _resolve_npc_id(node: Node) -> String:
    var cursor: Node = node
    while cursor != null:
        if cursor.has_meta("npc_id"):
            return str(cursor.get_meta("npc_id"))
        cursor = cursor.get_parent()
    return ""

func _run_interaction(npc_id: String) -> void:
    if NPCModule and NPCModule.has_method("start_npc_interaction"):
        await NPCModule.start_npc_interaction(npc_id)
    _is_interaction_active = false
