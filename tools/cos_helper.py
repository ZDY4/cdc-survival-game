#!/usr/bin/env python3
"""
腾讯COS上传脚本 - 上传CDC末日生存游戏H5版本
"""

import os
import sys
import json
from pathlib import Path
from datetime import datetime

try:
    from qcloud_cos import CosConfig, CosS3Client
except ImportError:
    print("正在安装腾讯云COS SDK...")
    import subprocess
    subprocess.run([sys.executable, "-m", "pip", "install", "cos-python-sdk-v5"])
    from qcloud_cos import CosConfig, CosS3Client

# 配置
PROJECT_PATH = Path("G:/project/cdc_survival_game")
EXPORT_PATH = PROJECT_PATH / "export" / "web"
COS_BASE_PATH = "games/cdc-h5/"

# MIME类型映射
MIME_TYPES = {
    '.html': 'text/html',
    '.js': 'application/javascript',
    '.wasm': 'application/wasm',
    '.pck': 'application/octet-stream',
    '.png': 'image/png',
    '.jpg': 'image/jpeg',
    '.svg': 'image/svg+xml',
    '.json': 'application/json',
    '.css': 'text/css',
}

def get_cos_client():
    """获取COS客户端"""
    # 从环境变量读取配置
    secret_id = os.environ.get('TENCENT_SECRET_ID')
    secret_key = os.environ.get('TENCENT_SECRET_KEY')
    region = os.environ.get('TENCENT_COS_REGION', 'ap-guangzhou')
    bucket = os.environ.get('TENCENT_COS_BUCKET')
    
    if not secret_id or not secret_key:
        print("错误：请设置环境变量 TENCENT_SECRET_ID 和 TENCENT_SECRET_KEY")
        print("示例：")
        print("  set TENCENT_SECRET_ID=your-secret-id")
        print("  set TENCENT_SECRET_KEY=your-secret-key")
        print("  set TENCENT_COS_BUCKET=your-bucket-name")
        return None
    
    if not bucket:
        bucket = input("请输入COS存储桶名称: ").strip()
    
    config = CosConfig(
        Region=region,
        SecretId=secret_id,
        SecretKey=secret_key,
        Token=None,
        Scheme='https'
    )
    
    return CosS3Client(config), bucket

def get_content_type(file_path: Path) -> str:
    """获取文件Content-Type"""
    suffix = file_path.suffix.lower()
    return MIME_TYPES.get(suffix, 'application/octet-stream')

def upload_file(client, bucket: str, local_path: Path, cos_key: str) -> bool:
    """上传单个文件"""
    try:
        content_type = get_content_type(local_path)
        file_size = local_path.stat().st_size / 1024  # KB
        
        print(f"  上传: {local_path.name} ({file_size:.1f} KB) - {content_type}")
        
        response = client.upload_file(
            Bucket=bucket,
            LocalFilePath=str(local_path),
            Key=cos_key,
            PartSize=1,
            MAXThread=10,
            EnableMD5=False,
            ContentType=content_type,
            CacheControl='max-age=3600',
        )
        
        return True
    except Exception as e:
        print(f"  ❌ 上传失败: {e}")
        return False

def upload_to_cos():
    """上传Web版本到腾讯COS"""
    print("=" * 60)
    print("CDC末日生存游戏 - H5版本上传")
    print("=" * 60)
    
    # 检查导出目录
    if not EXPORT_PATH.exists():
        print(f"❌ 导出目录不存在: {EXPORT_PATH}")
        print("请先运行 export_web.py 导出Web版本")
        return False
    
    # 检查必要文件
    required_files = ['index.html', 'index.js', 'index.wasm', 'index.pck']
    for file in required_files:
        if not (EXPORT_PATH / file).exists():
            print(f"❌ 缺少必要文件: {file}")
            return False
    
    # 获取COS客户端
    result = get_cos_client()
    if not result:
        return False
    
    client, bucket = result
    print(f"使用存储桶: {bucket}")
    print(f"上传路径: {COS_BASE_PATH}")
    print("-" * 60)
    
    # 上传文件
    uploaded = 0
    failed = 0
    
    for file_path in EXPORT_PATH.iterdir():
        if file_path.is_file():
            cos_key = f"{COS_BASE_PATH}{file_path.name}"
            
            if upload_file(client, bucket, file_path, cos_key):
                uploaded += 1
            else:
                failed += 1
    
    print("-" * 60)
    print(f"上传完成: {uploaded} 成功, {failed} 失败")
    
    if failed == 0:
        # 构建访问URL
        region = os.environ.get('TENCENT_COS_REGION', 'ap-guangzhou')
        url = f"https://{bucket}.cos.{region}.myqcloud.com/{COS_BASE_PATH}index.html"
        
        print("\n" + "=" * 60)
        print("✅ H5版本上传成功！")
        print("=" * 60)
        print(f"\n访问链接:")
        print(f"  {url}")
        print("\n二维码（使用微信/浏览器扫描）:")
        try:
            import qrcode
            qr = qrcode.QRCode(version=1, box_size=2, border=1)
            qr.add_data(url)
            qr.make(fit=True)
            qr.print_ascii(invert=True)
        except ImportError:
            print("  (安装 qrcode 库可显示二维码: pip install qrcode)")
        
        # 保存URL到文件
        url_file = EXPORT_PATH / "h5_url.txt"
        with open(url_file, 'w') as f:
            f.write(f"CDC末日生存游戏 H5版本\n")
            f.write(f"上传时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
            f.write(f"访问链接: {url}\n")
        print(f"\n访问链接已保存到: {url_file}")
        
        return True
    else:
        print("\n❌ 部分文件上传失败，请检查错误信息")
        return False

def main():
    try:
        if upload_to_cos():
            return 0
        return 1
    except Exception as e:
        print(f"\n❌ 发生错误: {e}")
        import traceback
        traceback.print_exc()
        return 1

if __name__ == "__main__":
    sys.exit(main())
