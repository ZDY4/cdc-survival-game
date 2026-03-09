# tests/sanity/test_file_integrity.gd
# 文件完整性测试 - Sanity Layer

extends Node
class_name SanityTest_FileIntegrity

const PROJECT_PATH = "res://"

# 必需文件列表
const REQUIRED_FILES = [
    "project.godot",
    "icon.svg"
]

# 必需模块
const REQUIRED_MODULES = [
    "core/event_bus.gd",
    "core/game_state.gd",
    "core/base_module.gd",
    "modules/dialog/dialog_module.gd",
    "modules/combat/combat_module.gd",
    "modules/inventory/inventory_module.gd",
    "modules/map/map_module.gd",
    "systems/save_system.gd"
]

# 必需场景
const REQUIRED_SCENES = [
    "scenes/ui/main_menu.tscn",
    "scenes/locations/game_world_3d.tscn",
    "modules/dialog/dialog_ui.tscn"
]

static func run_tests():
    runner.register_test(
        "project_file_exists",
        TestRunner.TestLayer.SANITY,
        TestRunner.TestPriority.P0_CRITICAL,
        _test_project_file_exists
    )
    
    runner.register_test(
        "core_modules_exist",
        TestRunner.TestLayer.SANITY,
        TestRunner.TestPriority.P0_CRITICAL,
        _test_core_modules_exist
    )
    
    runner.register_test(
        "scene_files_exist",
        TestRunner.TestLayer.SANITY,
        TestRunner.TestPriority.P0_CRITICAL,
        _test_scene_files_exist
    )
    
    runner.register_test(
        "autoload_configuration",
        TestRunner.TestLayer.SANITY,
        TestRunner.TestPriority.P0_CRITICAL,
        _test_autoload_configuration
    )
    
    runner.register_test(
        "icon_and_resources",
        TestRunner.TestLayer.SANITY,
        TestRunner.TestPriority.P1_MAJOR,
        _test_icon_and_resources
    )

static func _test_project_file_exists():
    var project_file = PROJECT_PATH + "project.godot"
    
    assert(FileAccess.file_exists(project_file), 
           "Project file not found: " + project_file)
    
    # 验证内容
    var file = FileAccess.open(project_file, FileAccess.READ)
    assert(file != null, "Cannot open project.godot")
    
    var content = file.get_as_text()
    file.close()
    
    assert(content.contains("config/name"), 
           "Project name not configured")
    assert(content.contains("run/main_scene"), 
           "Main scene not configured")

static func _test_core_modules_exist():
    for module_path in REQUIRED_MODULES:
        var full_path = PROJECT_PATH + module_path
        assert(FileAccess.file_exists(full_path), 
               "Required module not found: " + module_path)

static func _test_scene_files_exist():
    for scene_path in REQUIRED_SCENES:
        var full_path = PROJECT_PATH + scene_path
        assert(FileAccess.file_exists(full_path), 
               "Required scene not found: " + scene_path)

static func _test_autoload_configuration():
    var project_file = PROJECT_PATH + "project.godot"
    var file = FileAccess.open(project_file, FileAccess.READ)
    
    assert(file != null, "Cannot open project.godot")
    
    var content = file.get_as_text()
    file.close()
    
    # 检查必需的autoload
    var required_autoloads = [
        "EventBus",
        "GameState",
        "DialogModule",
        "CombatModule"
    ]
    
    for autoload in required_autoloads:
        assert(content.contains(autoload + "=\"*res://"), 
               "Autoload not configured: " + autoload)

static func _test_icon_and_resources():
    var icon_path = PROJECT_PATH + "icon.svg"
    assert(FileAccess.file_exists(icon_path), 
           "Project icon not found")

# 辅助断言函数
static func assert(condition: bool, message: String = ""):
    if not condition:
        push_error("SANITY TEST FAILED: " + message)
        # 在实际测试中这里会抛出异常
