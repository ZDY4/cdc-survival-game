#!/usr/bin/env python3
# test_via_api.py - 通过 AI Test Bridge API 测试游戏系统

import requests
import json
import time

def test_ai_bridge():
    """测试 AI Test Bridge 连接"""
    print("\n[测试] AI Test Bridge HTTP API")
    
    try:
        # 健康检查
        response = requests.get("http://localhost:8080/health", timeout=5)
        if response.status_code == 200:
            print("  [OK] HTTP 服务器响应正常")
            return True
        else:
            print(f"  [FAIL] 健康检查失败: {response.status_code}")
            return False
    except Exception as e:
        print(f"  [FAIL] 连接失败: {e}")
        return False

def test_game_state():
    """测试获取游戏状态"""
    print("\n[测试] 游戏状态 API")
    
    try:
        response = requests.get("http://localhost:8080/state", timeout=5)
        if response.status_code == 200:
            data = response.json()
            
            # 检查关键字段
            checks = []
            if "player" in data:
                checks.append("[OK] 玩家数据")
            if "inventory" in data:
                checks.append("[OK] 背包数据")
            if "world" in data:
                checks.append("[OK] 世界数据")
            
            for check in checks:
                print(f"  {check}")
            
            return len(checks) >= 3
        else:
            print(f"  [FAIL] 获取状态失败: {response.status_code}")
            return False
    except Exception as e:
        print(f"  [FAIL] 请求失败: {e}")
        return False

def test_actions():
    """测试执行操作"""
    print("\n[测试] 执行操作 API")
    
    actions_tested = 0
    actions_passed = 0
    
    # 测试搜索
    try:
        actions_tested += 1
        response = requests.post(
            "http://localhost:8080/execute",
            json={"action": "search", "parameters": {}},
            timeout=5
        )
        if response.status_code == 200:
            actions_passed += 1
            print("  [OK] 搜索操作")
    except Exception as e:
        print(f"  [FAIL] 搜索操作失败: {e}")
    
    # 测试存档
    try:
        actions_tested += 1
        response = requests.post(
            "http://localhost:8080/execute",
            json={"action": "sleep", "parameters": {}},
            timeout=5
        )
        if response.status_code == 200:
            result = response.json()
            if result.get("success"):
                actions_passed += 1
                print("  [OK] 存档操作")
    except Exception as e:
        print(f"  [FAIL] 存档操作失败: {e}")
    
    return actions_tested, actions_passed

def main():
    print("=" * 50)
    print("CDC 生存游戏 - API 测试")
    print("=" * 50)
    
    # 等待游戏启动
    print("\n等待游戏启动...")
    time.sleep(2)
    
    total_tests = 0
    passed_tests = 0
    
    # 测试 1: AI Bridge
    total_tests += 1
    if test_ai_bridge():
        passed_tests += 1
    
    # 测试 2: Game State
    total_tests += 1
    if test_game_state():
        passed_tests += 1
    
    # 测试 3: Actions
    actions_tested, actions_passed = test_actions()
    total_tests += actions_tested
    passed_tests += actions_passed
    
    # 报告
    print("\n" + "=" * 50)
    print(f"测试完成: {passed_tests}/{total_tests}")
    if total_tests > 0:
        pct = int(passed_tests / total_tests * 100)
        print(f"通过率: {pct}%")
        
        if passed_tests == total_tests:
            print("\n[SUCCESS] 所有 API 测试通过！")
        elif pct >= 80:
            print("\n[WARNING] 大部分 API 正常")
        else:
            print("\n[ERROR] 部分 API 需要检查")
    print("=" * 50)

if __name__ == "__main__":
    main()
