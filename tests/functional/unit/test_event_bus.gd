# tests/functional/unit/test_event_bus.gd
# EventBus 单元测试 - Functional Layer

extends Node
class_name FunctionalTest_EventBus

static func run_tests(runner: TestRunner) -> void:
    runner.register_test(
        "event_bus_singleton",
        TestRunner.TestLayer.FUNCTIONAL,
        TestRunner.TestPriority.P0_CRITICAL,
        _test_singleton
    )
    
    runner.register_test(
        "event_subscribe_and_emit",
        TestRunner.TestLayer.FUNCTIONAL,
        TestRunner.TestPriority.P0_CRITICAL,
        _test_subscribe_and_emit
    )
    
    runner.register_test(
        "event_multiple_listeners",
        TestRunner.TestLayer.FUNCTIONAL,
        TestRunner.TestPriority.P0_CRITICAL,
        _test_multiple_listeners
    )
    
    runner.register_test(
        "event_unsubscribe",
        TestRunner.TestLayer.FUNCTIONAL,
        TestRunner.TestPriority.P1_MAJOR,
        _test_unsubscribe
    )
    
    runner.register_test(
        "event_data_passing",
        TestRunner.TestLayer.FUNCTIONAL,
        TestRunner.TestPriority.P0_CRITICAL,
        _test_data_passing
    )

static func _test_singleton():
    # 确保 EventBus 是单例
    var bus1 = _get_event_bus()
    var bus2 = _get_event_bus()
    
    assert(bus1 != null, "EventBus should exist in scene tree")
    assert(bus1 == bus2, "EventBus should be singleton")

static func _test_subscribe_and_emit():
    var bus = _get_event_bus()
    assert(bus != null, "EventBus should exist in scene tree")
    var received = false
    var received_data = {}
    
    var callback = func(data):
        received = true
        received_data = data
    
    # 订阅事件
    bus.subscribe(bus.EventType.GAME_STARTED, callback)
    
    # 触发事件
    var test_data = {"test": true, "value": 42}
    bus.emit(bus.EventType.GAME_STARTED, test_data)
    
    # 等待一帧让信号处理
    await Engine.get_main_loop().process_frame
    
    assert(received, "Event listener should be called")
    assert(received_data.has("test"), "Event data should be passed")
    assert(received_data.test == true, "Event data should be correct")
    
    # 清理
    bus.unsubscribe(bus.EventType.GAME_STARTED, callback)

static func _test_multiple_listeners():
    var bus = _get_event_bus()
    assert(bus != null, "EventBus should exist in scene tree")
    var count = 0
    
    var callback1 = func(_data): count += 1
    var callback2 = func(_data): count += 1
    var callback3 = func(_data): count += 1
    
    bus.subscribe(bus.EventType.COMBAT_STARTED, callback1)
    bus.subscribe(bus.EventType.COMBAT_STARTED, callback2)
    bus.subscribe(bus.EventType.COMBAT_STARTED, callback3)
    
    bus.emit(bus.EventType.COMBAT_STARTED, {})
    
    await Engine.get_main_loop().process_frame
    
    assert(count == 3, "All 3 listeners should be called")
    
    # 清理
    bus.unsubscribe(bus.EventType.COMBAT_STARTED, callback1)
    bus.unsubscribe(bus.EventType.COMBAT_STARTED, callback2)
    bus.unsubscribe(bus.EventType.COMBAT_STARTED, callback3)

static func _test_unsubscribe():
    var bus = _get_event_bus()
    assert(bus != null, "EventBus should exist in scene tree")
    var received = false
    
    var callback = func(_data):
        received = true
    
    bus.subscribe(bus.EventType.DIALOG_STARTED, callback)
    bus.unsubscribe(bus.EventType.DIALOG_STARTED, callback)
    
    bus.emit(bus.EventType.DIALOG_STARTED, {})
    
    await Engine.get_main_loop().process_frame
    
    assert(not received, "Unsubscribed listener should not be called")

static func _test_data_passing():
    var bus = _get_event_bus()
    assert(bus != null, "EventBus should exist in scene tree")
    var complex_data = {
        "player_hp": 100,
        "enemy_name": "Zombie",
        "damage": 25,
        "items": ["sword", "shield"],
        "position": Vector2(100, 200)
    }
    
    var received_data = null
    
    var callback = func(data):
        received_data = data
    
    bus.subscribe(bus.EventType.PLAYER_HURT, callback)
    bus.emit(bus.EventType.PLAYER_HURT, complex_data)
    
    await Engine.get_main_loop().process_frame
    
    assert(received_data != null, "Complex data should be received")
    assert(received_data.player_hp == 100, "Nested data should be correct")
    assert(received_data.position == Vector2(100, 200), "Vector data should be correct")
    
    bus.unsubscribe(bus.EventType.PLAYER_HURT, callback)

static func _get_event_bus() -> Node:
    var loop = Engine.get_main_loop()
    if not (loop is SceneTree):
        return null
    var tree: SceneTree = loop
    if not tree.root:
        return null
    return tree.root.get_node_or_null("EventBus")
