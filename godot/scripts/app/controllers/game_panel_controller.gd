extends RefCounted

const HudSnapshot = preload("res://scripts/ui/snapshots/hud_snapshot.gd")
const DialogueSnapshot = preload("res://scripts/ui/snapshots/dialogue_snapshot.gd")
const InventorySnapshot = preload("res://scripts/ui/snapshots/inventory_snapshot.gd")
const TradeSnapshot = preload("res://scripts/ui/snapshots/trade_snapshot.gd")
const ContainerSnapshot = preload("res://scripts/ui/snapshots/container_snapshot.gd")
const JournalSnapshot = preload("res://scripts/ui/snapshots/journal_snapshot.gd")
const HUD_SCENE = preload("res://scenes/ui/hud.tscn")
const DIALOGUE_PANEL_SCENE = preload("res://scenes/ui/dialogue_panel.tscn")
const INVENTORY_PANEL_SCENE = preload("res://scenes/ui/inventory_panel.tscn")
const TRADE_PANEL_SCENE = preload("res://scenes/ui/trade_panel.tscn")
const CONTAINER_PANEL_SCENE = preload("res://scenes/ui/container_panel.tscn")
const JOURNAL_PANEL_SCENE = preload("res://scenes/ui/journal_panel.tscn")

var parent: Node
var registry: RefCounted
var simulation: RefCounted
var world_result: Dictionary
var active_trade_target: Dictionary = {}

var hud: Control
var dialogue_panel: Control
var inventory_panel: Control
var trade_panel: Control
var container_panel: Control
var journal_panel: Control


func _init(p_parent: Node, p_registry: RefCounted, p_simulation: RefCounted, p_world_result: Dictionary) -> void:
	parent = p_parent
	registry = p_registry
	simulation = p_simulation
	world_result = p_world_result


func setup_panels() -> void:
	hud = _ensure_panel(hud, HUD_SCENE, "Hud")
	dialogue_panel = _ensure_panel(dialogue_panel, DIALOGUE_PANEL_SCENE, "DialoguePanelRoot")
	inventory_panel = _ensure_panel(inventory_panel, INVENTORY_PANEL_SCENE, "InventoryPanelRoot")
	trade_panel = _ensure_panel(trade_panel, TRADE_PANEL_SCENE, "TradePanelRoot")
	container_panel = _ensure_panel(container_panel, CONTAINER_PANEL_SCENE, "ContainerPanelRoot")
	journal_panel = _ensure_panel(journal_panel, JOURNAL_PANEL_SCENE, "JournalPanelRoot")


func refresh_all(selected_prompt: Dictionary = {}) -> void:
	refresh_hud(selected_prompt)
	refresh_dialogue_panel()
	refresh_inventory_panel()
	refresh_trade_panel()
	refresh_container_panel()
	refresh_journal_panel()


func refresh_hud(selected_prompt: Dictionary = {}) -> void:
	if hud == null or simulation == null:
		return
	var snapshot: Dictionary = HudSnapshot.new().build(simulation.snapshot(), world_result, selected_prompt)
	hud.apply_snapshot(snapshot)


func refresh_dialogue_panel() -> void:
	if dialogue_panel == null or simulation == null:
		return
	dialogue_panel.apply_snapshot(DialogueSnapshot.new(registry).build(simulation.snapshot()))


func refresh_inventory_panel() -> void:
	if inventory_panel == null or simulation == null:
		return
	inventory_panel.apply_snapshot(InventorySnapshot.new(registry).build(simulation.snapshot()))


func refresh_trade_panel() -> void:
	if trade_panel == null or simulation == null:
		return
	trade_panel.apply_snapshot(TradeSnapshot.new(registry).build(simulation.snapshot(), active_trade_target))


func refresh_container_panel() -> void:
	if container_panel == null or simulation == null:
		return
	container_panel.apply_snapshot(ContainerSnapshot.new(registry).build(simulation.snapshot()))


func refresh_journal_panel() -> void:
	if journal_panel == null or simulation == null:
		return
	journal_panel.apply_snapshot(JournalSnapshot.new(registry).build(simulation.snapshot()))


func update_world_result(value: Dictionary) -> void:
	world_result = value


func close_trade_panel() -> void:
	active_trade_target = {}
	refresh_trade_panel()


func _ensure_panel(current: Control, scene: PackedScene, node_name: String) -> Control:
	if current != null:
		return current
	var panel: Control = scene.instantiate()
	panel.name = node_name
	parent.add_child(panel)
	return panel
