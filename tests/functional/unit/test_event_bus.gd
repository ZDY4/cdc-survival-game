# tests/functional/unit/test_event_bus.gd
# EventBus 单元测试 - Functional Layer

extends Node
class_name FunctionalTest_EventBus

static func run_tests():
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
    var bus1 = EventBus
    var bus2 = EventBus
    
    assert(bus1 == bus2, "EventBus should be singleton")

static func _test_subscribe_and_emit():
    var received = false
    var received_data = {}
    
    var callback = func(data):
        received = true
        received_data = data
    
    # 订阅事件
    EventBus.subscribe(EventBus.EventType.GAME_STARTED, callback)
    
    # 触发事件
    var test_data = {"test": true, "value": 42}
    EventBus.emit(EventBus.EventType.GAME_STARTED, test_data)
    
    # 等待一帧让信号处理
    await Engine.get_main_loop().process_frame
    
    assert(received, "Event listener should be called")
    assert(received_data.has("test"), "Event data should be passed")
    assert(received_data.test == true, "Event data should be correct")
    
    # 清理
    EventBus.unsubscribe(EventBus.EventType.GAME_STARTED, callback)

static func _test_multiple_listeners():
    var count = 0
    
    var callback1 = func(_data): count += 1
    var callback2 = func(_data): count += 1
    var callback3 = func(_data): count += 1
    
    EventBus.subscribe(EventBus.EventType.COMBAT_STARTED, callback1)
    EventBus.subscribe(EventBus.EventType.COMBAT_STARTED, callback2)
    EventBus.subscribe(EventBus.EventType.COMBAT_STARTED, callback3)
    
    EventBus.emit(EventBus.EventType.COMBAT_STARTED, {})
    
    await Engine.get_main_loop().process_frame
    
    assert(count == 3, "All 3 listeners should be called")
    
    # 清理
    EventBus.unsubscribe(EventBus.EventType.COMBAT_STARTED, callback1)
    EventBus.unsubscribe(EventBus.EventType.COMBAT_STARTED, callback2)
    EventBus.unsubscribe(EventBus.EventType.COMBAT_STARTED, callback3)

static func _test_unsubscribe():
    var received = false
    
    var callback = func(_data):
        received = true
    
    EventBus.subscribe(EventBus.EventType.DIALOG_STARTED, callback)
    EventBus.unsubscribe(EventBus.EventType.DIALOG_STARTED, callback)
    
    EventBus.emit(EventBus.EventType.DIALOG_STARTED, {})
    
    await Engine.get_main_loop().process_frame
    
    assert(not received, "Unsubscribed listener should not be called")

static func _test_data_passing():
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
    
    EventBus.subscribe(EventBus.EventType.PLAYER_HURT, callback)
    EventBus.emit(EventBus.EventType.PLAYER_HURT, complex_data)
    
    await Engine.get_main_loop().process_frame
    
    assert(received_data != null, "Complex data should be received")
    assert(received_data.player_hp == 100, "Nested data should be correct")
    assert(received_data.position == Vector2(100, 200), "Vector data should be correct")
    
    EventBus.unsubscribe(EventBus.EventType.PLAYER_HURT, callback)
