# tests/agent/agent_base.py
# Agent 测试基类 - Agent Layer
# 用于AI驱动的探索性测试

import requests
import json
import time
import random
import os
from abc import ABC, abstractmethod
from typing import Dict, List, Any, Optional
from dataclasses import dataclass
from enum import Enum

class AgentAction(Enum):
    TRAVEL = "travel"
    SEARCH = "search"
    TALK = "talk"
    ATTACK = "attack"
    USE_ITEM = "use_item"
    SLEEP = "sleep"
    WAIT = "wait"

@dataclass
class GameState:
    """游戏状态快照"""
    player_hp: int
    player_max_hp: int
    hunger: int
    thirst: int
    location: str
    location_name: str
    inventory_count: int
    inventory_max: int
    available_actions: List[str]
    timestamp: float
    
    @property
    def is_healthy(self) -> bool:
        return self.player_hp > self.player_max_hp * 0.5
    
    @property
    def is_in_danger(self) -> bool:
        return self.player_hp < self.player_max_hp * 0.3

class CDCAgentBase(ABC):
    """CDC 测试 Agent 基类"""
    
    def __init__(self, api_url: str = "http://localhost:8080"):
        self.api_url = api_url
        self.current_state: Optional[GameState] = None
        self.action_history: List[Dict] = []
        self.test_results: List[Dict] = []
        self.running = False
        
    # ==================== 基础API方法 ====================
    
    def get_state(self) -> GameState:
        """获取当前游戏状态"""
        try:
            response = requests.get(f"{self.api_url}/state", timeout=5)
            payload = response.json()
            data = payload.get("data", payload) if isinstance(payload, dict) else {}

            player = data.get("player", {})
            inventory = data.get("inventory", {})
            location = data.get("location", {})
            world = data.get("world", {})

            inventory_items = inventory.get("items", [])
            if isinstance(inventory_items, list):
                inventory_count = inventory.get("used_slots", inventory.get("count", len(inventory_items)))
            else:
                inventory_count = inventory.get("used_slots", inventory.get("count", 0))

            available_actions = data.get("available_actions", [])
            if not isinstance(available_actions, list) or len(available_actions) == 0:
                available_actions = self.fetch_actions()

            self.current_state = GameState(
                player_hp=int(player.get("hp", 0)),
                player_max_hp=int(player.get("max_hp", max(int(player.get("hp", 0)), 1))),
                hunger=int(player.get("hunger", 0)),
                thirst=int(player.get("thirst", 0)),
                location=str(location.get("current", player.get("position", world.get("day", "unknown")))),
                location_name=str(location.get("current_name", data.get("scene", "unknown"))),
                inventory_count=int(inventory_count),
                inventory_max=int(inventory.get("max_slots", max(int(inventory_count), 0))),
                available_actions=available_actions,
                timestamp=float(data.get("timestamp", time.time()))
            )
            return self.current_state
            
        except Exception as e:
            self._log_error(f"Failed to get state: {e}")
            return None

    def fetch_actions(self) -> List[str]:
        """从 /actions 获取可用动作名"""
        try:
            response = requests.get(f"{self.api_url}/actions", timeout=5)
            if response.status_code != 200:
                return []
            data = response.json()
            actions = data.get("actions", [])
            names: List[str] = []
            for item in actions:
                if isinstance(item, dict):
                    name = item.get("name", "")
                    if isinstance(name, str) and name:
                        names.append(name)
            return names
        except Exception as e:
            self._log_error(f"Failed to fetch actions: {e}")
            return []
    
    def execute_action(self, action_type: str, parameters: Dict = None) -> Dict:
        """执行游戏操作"""
        if parameters is None:
            parameters = {}
            
        try:
            response = requests.post(
                f"{self.api_url}/execute",
                json={"action": action_type, "params": parameters},
                timeout=10
            )
            payload = response.json()
            result = payload.get("result", payload) if isinstance(payload, dict) else {"success": False, "message": "Invalid response"}
            
            # 记录操作历史
            self.action_history.append({
                "action": action_type,
                "parameters": parameters,
                "result": result,
                "timestamp": time.time()
            })
            
            return result
            
        except Exception as e:
            self._log_error(f"Action failed: {e}")
            return {"success": False, "message": str(e)}
    
    def health_check(self) -> bool:
        """检查游戏服务器健康状态"""
        try:
            response = requests.get(f"{self.api_url}/health", timeout=5)
            return response.status_code == 200
        except:
            return False
    
    # ==================== 决策方法 ====================
    
    @abstractmethod
    def decide_next_action(self) -> tuple:
        """
        决定下一个操作
        返回: (action_type, parameters)
        子类必须实现此方法
        """
        pass
    
    def get_available_actions(self) -> List[str]:
        """获取当前可用的操作列表"""
        if not self.current_state:
            return []
        return self.current_state.available_actions
    
    def is_action_available(self, action: str) -> bool:
        """检查某个操作是否可用"""
        return action in self.get_available_actions()
    
    # ==================== 测试执行 ====================
    
    def run_test(self, max_actions: int = 100, duration_seconds: float = None):
        """
        运行Agent测试
        
        Args:
            max_actions: 最大操作次数
            duration_seconds: 最大运行时间(秒)，None表示不限制
        """
        if not self.health_check():
            print("❌ Game server not available")
            return
        
        self.running = True
        start_time = time.time()
        action_count = 0
        
        print(f"🚀 Starting Agent test...")
        print(f"   Max actions: {max_actions}")
        print(f"   Max duration: {duration_seconds}s" if duration_seconds else "   Max duration: unlimited")
        print()
        
        try:
            while self.running and action_count < max_actions:
                # 检查时间限制
                if duration_seconds and (time.time() - start_time) > duration_seconds:
                    print("⏱️ Duration limit reached")
                    break
                
                # 获取当前状态
                state = self.get_state()
                if not state:
                    print("❌ Failed to get game state")
                    break
                
                # 决策
                action_type, parameters = self.decide_next_action()
                
                if not action_type:
                    print("🤔 No action decided, waiting...")
                    time.sleep(1)
                    continue
                
                # 执行操作
                result = self.execute_action(action_type, parameters)
                action_count += 1
                
                # 检查结果
                if not result.get("success"):
                    self._log_error(f"Action failed: {result.get('message')}")
                
                # 显示进度
                if action_count % 10 == 0:
                    elapsed = time.time() - start_time
                    print(f"   Progress: {action_count} actions, {elapsed:.1f}s elapsed")
                
                # 短暂等待
                time.sleep(0.5)
                
        except KeyboardInterrupt:
            print("\n⚠️ Test interrupted by user")
        except Exception as e:
            print(f"\n❌ Test error: {e}")
        finally:
            self.running = False
            self._generate_report()
    
    def stop(self):
        """停止测试"""
        self.running = False
    
    # ==================== 报告和日志 ====================
    
    def _log_error(self, message: str):
        """记录错误"""
        print(f"❌ {message}")
        self.test_results.append({
            "type": "error",
            "message": message,
            "timestamp": time.time()
        })
    
    def _log_info(self, message: str):
        """记录信息"""
        print(f"ℹ️ {message}")
    
    def _generate_report(self):
        """生成测试报告"""
        total_actions = len(self.action_history)
        successful_actions = sum(1 for a in self.action_history if a["result"].get("success"))
        errors = len([r for r in self.test_results if r["type"] == "error"])
        
        print()
        print("=" * 50)
        print("📊 AGENT TEST REPORT")
        print("=" * 50)
        print(f"Total actions: {total_actions}")
        print(f"Successful: {successful_actions}")
        print(f"Failed: {total_actions - successful_actions}")
        print(f"Errors: {errors}")
        print(f"Success rate: {successful_actions/max(total_actions,1)*100:.1f}%")
        print("=" * 50)
        
        # 保存详细报告
        report = {
            "summary": {
                "total_actions": total_actions,
                "successful": successful_actions,
                "failed": total_actions - successful_actions,
                "errors": errors,
                "success_rate": successful_actions / max(total_actions, 1)
            },
            "action_history": self.action_history[-50:],  # 最近50个操作
            "errors": [r for r in self.test_results if r["type"] == "error"]
        }

        os.makedirs("tests/results", exist_ok=True)
        with open("tests/results/agent_test_report.json", "w", encoding="utf-8") as f:
            json.dump(report, f, indent=2)
        
        print("📄 Detailed report saved to: tests/results/agent_test_report.json")

# ==================== 示例Agent实现 ====================

class RandomExplorationAgent(CDCAgentBase):
    """随机探索Agent - 用于基础测试"""
    
    def decide_next_action(self) -> tuple:
        """随机选择可用操作"""
        if not self.current_state:
            return AgentAction.WAIT.value, {}
        
        available = self.get_available_actions()
        if not available:
            return AgentAction.WAIT.value, {}
        
        # 根据健康状态调整行为
        if self.current_state.is_in_danger:
            # 危险时优先治疗或逃跑
            if "sleep" in available:
                return AgentAction.SLEEP.value, {}
        
        # 随机选择
        action = random.choice(available)
        
        # 解析操作
        if action.startswith("travel:"):
            dest = action.replace("travel:", "")
            return AgentAction.TRAVEL.value, {"destination": dest}
        elif action == "search":
            return AgentAction.SEARCH.value, {}
        elif action == "sleep":
            return AgentAction.SLEEP.value, {}
        else:
            return AgentAction.WAIT.value, {}

class SurvivalFocusedAgent(CDCAgentBase):
    """生存导向Agent - 专注于保持健康"""
    
    def decide_next_action(self) -> tuple:
        """优先保证生存"""
        if not self.current_state:
            return AgentAction.WAIT.value, {}
        
        available = self.get_available_actions()
        
        # 低血量时优先休息
        if self.current_state.player_hp < 30:
            if "sleep" in available:
                return AgentAction.SLEEP.value, {}
        
        # 饥饿时搜索食物
        if self.current_state.hunger < 20:
            if "search" in available:
                return AgentAction.SEARCH.value, {}
        
        # 否则随机探索
        if available:
            action = random.choice(available)
            if action.startswith("travel:"):
                return AgentAction.TRAVEL.value, {"destination": action.replace("travel:", "")}
            if action in ("search", "sleep", "wait"):
                return action, {}
        return AgentAction.WAIT.value, {}

if __name__ == "__main__":
    # 示例运行
    agent = RandomExplorationAgent()
    agent.run_test(max_actions=50, duration_seconds=60)
