#!/usr/bin/env python3
"""
Web导出脚本 - 使用Godot 4.6导出Web版本
"""

import os
import sys
import subprocess
import shutil
from pathlib import Path

# 配置
PROJECT_PATH = Path("G:/project/cdc_survival_game")
EXPORT_PATH = PROJECT_PATH / "export" / "web"
GODOT_EXECUTABLE = "godot"  # 假设godot在PATH中

def check_godot():
    """检查Godot是否可用"""
    try:
        result = subprocess.run([GODOT_EXECUTABLE, "--version"], 
                              capture_output=True, text=True)
        print(f"Godot版本: {result.stdout.strip()}")
        return True
    except FileNotFoundError:
        print("错误：找不到Godot可执行文件")
        print("请确保Godot 4.6已安装并在PATH中")
        return False

def check_export_templates():
    """检查Web导出模板"""
    print("检查Web导出模板...")
    # 模板路径通常在用户目录下
    home = Path.home()
    
    # 检查可能的模板路径
    template_paths = [
        home / "AppData" / "Roaming" / "Godot" / "export_templates",
        home / "AppData" / "Local" / "Godot" / "export_templates",
        home / ".local" / "share" / "godot" / "export_templates",
        home / "Library" / "Application Support" / "Godot" / "export_templates",
    ]
    
    for template_path in template_paths:
        if template_path.exists():
            print(f"找到模板目录: {template_path}")
            # 检查是否有Web模板
            web_templates = list(template_path.glob("*/web_*"))
            if web_templates:
                print(f"找到Web模板: {web_templates}")
                return True
    
    print("警告：未找到Web导出模板")
    print("请从Godot编辑器下载Web导出模板：")
    print("编辑器 -> 管理 -> 模板 -> 下载并安装")
    return False

def export_web():
    """导出Web版本"""
    print("=" * 50)
    print("开始导出CDC末日生存游戏 Web版本")
    print("=" * 50)
    
    # 检查Godot
    if not check_godot():
        return False
    
    # 检查导出模板
    check_export_templates()
    
    # 清理旧导出
    if EXPORT_PATH.exists():
        print(f"清理旧导出目录: {EXPORT_PATH}")
        shutil.rmtree(EXPORT_PATH)
    
    EXPORT_PATH.mkdir(parents=True, exist_ok=True)
    
    # 执行导出
    print("正在导出Web版本...")
    cmd = [
        GODOT_EXECUTABLE,
        "--path", str(PROJECT_PATH),
        "--export-release", "Web",
        str(EXPORT_PATH / "index.html")
    ]
    
    print(f"执行命令: {' '.join(cmd)}")
    
    try:
        result = subprocess.run(cmd, capture_output=True, text=True)
        print(result.stdout)
        if result.stderr:
            print("错误输出:", result.stderr)
        
        if result.returncode == 0:
            print("✅ 导出成功！")
            return True
        else:
            print(f"❌ 导出失败，返回码: {result.returncode}")
            return False
    except Exception as e:
        print(f"导出过程中出错: {e}")
        return False

def check_export_files():
    """检查导出文件"""
    print("\n检查导出文件...")
    
    if not EXPORT_PATH.exists():
        print(f"❌ 导出目录不存在: {EXPORT_PATH}")
        return False
    
    required_files = ["index.html", "index.js", "index.wasm", "index.pck"]
    missing = []
    
    for file in required_files:
        file_path = EXPORT_PATH / file
        if file_path.exists():
            size = file_path.stat().st_size / (1024 * 1024)  # MB
            print(f"  ✅ {file}: {size:.2f} MB")
        else:
            print(f"  ❌ {file}: 缺失")
            missing.append(file)
    
    if missing:
        print(f"\n❌ 缺少文件: {missing}")
        return False
    
    # 计算总大小
    total_size = sum(f.stat().st_size for f in EXPORT_PATH.iterdir()) / (1024 * 1024)
    print(f"\n导出文件总大小: {total_size:.2f} MB")
    
    if total_size > 30:
        print("⚠️ 警告：文件大小超过30MB限制！")
    else:
        print("✅ 文件大小符合要求")
    
    return True

def create_http_server_script():
    """创建HTTP服务器启动脚本"""
    server_script = EXPORT_PATH / "start_server.py"
    content = '''#!/usr/bin/env python3
"""简单的HTTP服务器用于测试Web版本"""
import http.server
import socketserver
import os

PORT = 8080
DIRECTORY = os.path.dirname(os.path.abspath(__file__))

class MyHTTPRequestHandler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        # 添加必要的CORS和安全头
        self.send_header('Cross-Origin-Opener-Policy', 'same-origin')
        self.send_header('Cross-Origin-Embedder-Policy', 'require-corp')
        self.send_header('Access-Control-Allow-Origin', '*')
        super().end_headers()

    def translate_path(self, path):
        return os.path.join(DIRECTORY, path.lstrip('/'))

if __name__ == "__main__":
    os.chdir(DIRECTORY)
    with socketserver.TCPServer(("", PORT), MyHTTPRequestHandler) as httpd:
        print(f"服务器运行在 http://localhost:{PORT}")
        print("按 Ctrl+C 停止服务器")
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\\n服务器已停止")
'''
    
    with open(server_script, 'w') as f:
        f.write(content)
    
    print(f"\n已创建HTTP服务器脚本: {server_script}")
    print("运行以下命令启动测试服务器:")
    print(f"  cd {EXPORT_PATH}")
    print(f"  python start_server.py")
    print(f"  然后在浏览器打开: http://localhost:8080")

def main():
    # 导出
    if export_web():
        # 检查导出文件
        if check_export_files():
            # 创建HTTP服务器脚本
            create_http_server_script()
            
            print("\n" + "=" * 50)
            print("导出完成！")
            print(f"导出目录: {EXPORT_PATH}")
            print("=" * 50)
            return 0
    
    return 1

if __name__ == "__main__":
    sys.exit(main())
