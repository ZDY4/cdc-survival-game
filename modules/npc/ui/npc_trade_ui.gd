extends Control
## NPC交易UI
## 显示交易界面，支持拖放交易

class_name NPCTradeUI

const NPCTradeComponent = preload("res://modules/npc/components/npc_trade_component.gd")
const NPCData = preload("res://modules/npc/npc_data.gd")

signal trade_finished

var trade_component: NPCTradeComponent
var npc_data: NPCData
var total_profit: int = 0

# 节点引用
@onready var player_inventory_list: ItemList
@onready var npc_inventory_list: ItemList
@onready var player_info_label: Label
@onready var npc_info_label: Label
@onready var trade_preview_label: Label
@onready var confirm_button: Button
@onready var cancel_button: Button

func initialize(component: NPCTradeComponent, data: NPCData):
	trade_component = component
	npc_data = data

func _ready():
	_setup_ui()
	_load_inventories()
	_update_info()

func _setup_ui():
	# 创建UI布局
	anchors_preset = PRESET_FULL_RECT
	
	var center_panel = Panel.new()
	center_panel.set_anchors_preset(PRESET_CENTER)
	center_panel.custom_minimum_size = Vector2(800, 600)
	add_child(center_panel)
	
	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 10)
	center_panel.add_child(vbox)
	
	# 标题
	var title = Label.new()
	title.text = "与 %s 交易" % (npc_data.name if npc_data else "商人")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	vbox.add_child(title)
	
	# 信息栏
	var info_hbox = HBoxContainer.new()
	vbox.add_child(info_hbox)
	
	player_info_label = Label.new()
	player_info_label.text = "你的背包"
	info_hbox.add_child(player_info_label)
	
	info_hbox.add_spacer(false)
	
	npc_info_label = Label.new()
	npc_info_label.text = "%s的商店" % (npc_data.name if npc_data else "商人")
	info_hbox.add_child(npc_info_label)
	
	# 库存列表
	var lists_hbox = HBoxContainer.new()
	lists_hbox.size_flags_vertical = SIZE_EXPAND_FILL
	vbox.add_child(lists_hbox)
	
	# 玩家库存
	player_inventory_list = ItemList.new()
	player_inventory_list.size_flags_horizontal = SIZE_EXPAND_FILL
	player_inventory_list.size_flags_vertical = SIZE_EXPAND_FILL
	player_inventory_list.item_selected.connect(_on_player_item_selected)
	lists_hbox.add_child(player_inventory_list)
	
	# 中间按钮
	var button_vbox = VBoxContainer.new()
	button_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	lists_hbox.add_child(button_vbox)
	
	var buy_btn = Button.new()
	buy_btn.text = "<< 买入"
	buy_btn.pressed.connect(_on_buy_pressed)
	button_vbox.add_child(buy_btn)
	
	var sell_btn = Button.new()
	sell_btn.text = "卖出 >>"
	sell_btn.pressed.connect(_on_sell_pressed)
	button_vbox.add_child(sell_btn)
	
	# NPC库存
	npc_inventory_list = ItemList.new()
	npc_inventory_list.size_flags_horizontal = SIZE_EXPAND_FILL
	npc_inventory_list.size_flags_vertical = SIZE_EXPAND_FILL
	npc_inventory_list.item_selected.connect(_on_npc_item_selected)
	lists_hbox.add_child(npc_inventory_list)
	
	# 交易预览
	trade_preview_label = Label.new()
	trade_preview_label.text = "选择物品进行交易"
	trade_preview_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(trade_preview_label)
	
	# 底部按钮
	var bottom_hbox = HBoxContainer.new()
	bottom_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(bottom_hbox)
	
	confirm_button = Button.new()
	confirm_button.text = "确认"
	confirm_button.pressed.connect(_on_confirm_pressed)
	bottom_hbox.add_child(confirm_button)
	
	cancel_button = Button.new()
	cancel_button.text = "取消"
	cancel_button.pressed.connect(_on_cancel_pressed)
	bottom_hbox.add_child(cancel_button)

func _load_inventories():
	# 加载NPC库存
	npc_inventory_list.clear()
	if npc_data and npc_data.trade_data:
		for item in npc_data.trade_data.inventory:
			var item_name = item.get("id", "未知")
			var count = item.get("count", 1)
			var price = item.get("price", 0)
			
			# 计算实际价格
			if trade_component:
				price = trade_component.calculate_buy_price(item_name, price)
			
			var display_text = "%s x%d (%d)" % [item_name, count, price]
			var idx = npc_inventory_list.add_item(display_text)
			npc_inventory_list.set_item_metadata(idx, item)
	
	# 加载玩家库存
	player_inventory_list.clear()
	if InventoryModule:
		for item_id in InventoryModule.get_all_items():
			var count = InventoryModule.get_item_count(item_id)
			var base_price = 10  # TODO: 获取物品基础价格
			
			# 计算出售价格
			var price = base_price
			if trade_component:
				price = trade_component.calculate_sell_price(item_id, base_price)
			
			var display_text = "%s x%d (%d)" % [item_id, count, price]
			var idx = player_inventory_list.add_item(display_text)
			player_inventory_list.set_item_metadata(idx, {"id": item_id, "count": count, "price": price})

func _update_info():
	if npc_data:
		var mood_level = npc_data.get_friendlyness_level()
		var discount = 0
		
		if trade_component:
			var charisma = 10  # TODO: 获取玩家魅力
			discount = (charisma - 10) * 2 + (npc_data.mood.friendliness - 50)
		
		npc_info_label.text = "%s的商店 [友好度:%s 折扣:%d%%]" % [npc_data.name, mood_level, discount]

func _on_player_item_selected(index: int):
	var item = player_inventory_list.get_item_metadata(index)
	var item_id = item.get("id", "")
	var price = item.get("price", 0)
	
	trade_preview_label.text = "出售 %s 可获得 %d" % [item_id, price]

func _on_npc_item_selected(index: int):
	var item = npc_inventory_list.get_item_metadata(index)
	var item_id = item.get("id", "")
	var price = item.get("price", 0)
	
	# 重新计算价格
	if trade_component:
		price = trade_component.calculate_buy_price(item_id, price)
	
	trade_preview_label.text = "购买 %s 需要 %d" % [item_id, price]

func _on_buy_pressed():
	var selected = npc_inventory_list.get_selected_items()
	if selected.is_empty():
		return
	
	var idx = selected[0]
	var item = npc_inventory_list.get_item_metadata(idx)
	var item_id = item.get("id", "")
	var count = 1  # TODO: 支持选择数量
	
	if trade_component:
		var result = trade_component.buy_item(item_id, count)
		if result.success:
			total_profit -= result.price
			_load_inventories()
			trade_preview_label.text = "购买成功！花费 %d" % result.price
		else:
			trade_preview_label.text = "购买失败: %s" % result.reason

func _on_sell_pressed():
	var selected = player_inventory_list.get_selected_items()
	if selected.is_empty():
		return
	
	var idx = selected[0]
	var item = player_inventory_list.get_item_metadata(idx)
	var item_id = item.get("id", "")
	var count = 1  # TODO: 支持选择数量
	
	if trade_component:
		var result = trade_component.sell_item(item_id, count)
		if result.success:
			total_profit += result.price
			_load_inventories()
			trade_preview_label.text = "出售成功！获得 %d" % result.price
		else:
			trade_preview_label.text = "出售失败: %s" % result.reason

func _on_confirm_pressed():
	trade_finished.emit()

func _on_cancel_pressed():
	trade_finished.emit()
