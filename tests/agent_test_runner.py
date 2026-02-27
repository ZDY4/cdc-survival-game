#!/usr/bin/env python3
# agent_test_runner.py - Agent 测试运行器

import requests
import json
import time
import random
from typing import Dict, List, Optional

class CDCAgent:
    """CDC 生存游戏测试 Agent"""
    
    def __init__(self, api_url: str = "http://localhost:8080"):
        self.api_url = api_url
        self.action_history: List[Dict] = []
        self.errors: List[str] = []
        self.running = False
    
    def get_state(self) -> Optional[Dict]:
        """获取游戏状态"""
        try:
            response = requests.get(f"{self.api_url}/state", timeout=5)
            if response.status_code == 200:
                return response.json()
        except Exception as e:
            self.errors.append(f"Get state failed: {e}")
        return None
    
    def execute_action(self, action_type: str, params: Dict = None) -> Dict:
        """执行游戏操作"""
        if params is None:
            params = {}
        
        try:
            response = requests.post(
                f"{self.api_url}/execute",
                json={"action": action_type, "parameters": params},
                timeout=10
            )
            result = response.json()
            
            self.action_history.append({
                "action": action_type,
                "params": params,
                "result": result,
                "time": time.time()
            })
            
            return result
        except Exception as e:
            error_result = {"success": False, "message": str(e)}
            self.errors.append(f"Action {action_type} failed: {e}")
            return error_result
    
    def decide_action(self, state: Dict) -> tuple:
        """决定下一个操作"""
        if not state:
            return "wait", {}
        
        player = state.get("player", {})
        hp = player.get("hp", 100)
        hunger = player.get("hunger", 100)
        
        # 低血量时优先休息
        if hp < 30:
            return "sleep", {}
        
        # 饥饿时搜索
        if hunger < 30:
            return "search", {}
        
        # 随机选择可用操作
        actions = ["search", "sleep"]
        
        # 如果有目的地可以旅行
        location = state.get("location", {})
        destinations = location.get("available_destinations", [])
        if destinations:
            dest = random.choice(destinations)
            actions.append(("travel", {"destination": dest.get("id", "street_a")}))
        
        choice = random.choice(actions)
        if isinstance(choice, tuple):
            return choice
        return choice, {}
    
    def run_test(self, max_actions: int = 30, duration: int = 60):
        """运行 Agent 测试"""
        print("=" * 60)
        print("CDC SURVIVAL GAME - AGENT TEST")
        print("=" * 60)
        
        # 检查游戏连接
        print("\n[1] Checking game connection...")
        try:
            response = requests.get(f"{self.api_url}/health", timeout=5)
            if response.status_code == 200:
                print("    [OK] Game is running")
            else:
                print(f"    [FAIL] Health check failed: {response.status_code}")
                return
        except Exception as e:
            print(f"    [FAIL] Cannot connect to game: {e}")
            print("    Make sure the game is running!")
            return
        
        # 运行测试
        print(f"\n[2] Running {max_actions} actions (max {duration}s)...")
        print("-" * 60)
        
        self.running = True
        start_time = time.time()
        action_count = 0
        success_count = 0
        
        while self.running and action_count < max_actions:
            # 检查时间限制
            if time.time() - start_time > duration:
                print("\n[TIMEOUT] Duration limit reached")
                break
            
            # 获取状态
            state = self.get_state()
            if not state:
                print("[ERROR] Failed to get game state")
                break
            
            # 显示当前状态
            if action_count % 5 == 0:
                player = state.get("player", {})
                print(f"\n[Action {action_count}] HP:{player.get('hp', '?')} "
                      f"Hunger:{player.get('hunger', '?')} "
                      f"Loc:{state.get('location', {}).get('current', '?')}")
            
            # 决定并执行操作
            action, params = self.decide_action(state)
            result = self.execute_action(action, params)
            action_count += 1
            
            if result.get("success"):
                success_count += 1
                print(f"  [OK] {action}: {result.get('message', 'Success')[:50]}")
            else:
                print(f"  [FAIL] {action}: {result.get('message', 'Failed')[:50]}")
            
            # 短暂等待
            time.sleep(0.5)
        
        self.running = False
        
        # 生成报告
        self._generate_report(action_count, success_count, start_time)
    
    def _generate_report(self, total: int, success: int, start_time: float):
        """生成测试报告"""
        duration = time.time() - start_time
        fail = total - success
        
        print("\n" + "=" * 60)
        print("AGENT TEST REPORT")
        print("=" * 60)
        print(f"Total Actions:   {total}")
        print(f"Successful:      {success}")
        print(f"Failed:          {fail}")
        print(f"Success Rate:    {success/max(total,1)*100:.1f}%")
        print(f"Duration:        {duration:.1f}s")
        
        if self.errors:
            print(f"\nErrors ({len(self.errors)}):")
            for i, error in enumerate(self.errors[:5]):
                print(f"  {i+1}. {error[:60]}")
        
        print("\n" + "=" * 60)
        
        if success == total:
            print("[SUCCESS] All actions completed successfully!")
        elif success / max(total, 1) >= 0.8:
            print("[GOOD] Most actions completed successfully")
        else:
            print("[WARNING] Several actions failed, check the game state")
        
        print("=" * 60)

if __name__ == "__main__":
    agent = CDCAgent()
    agent.run_test(max_actions=20, duration=30)
