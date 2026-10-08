#!/usr/bin/env python3
"""
sing-box 配置管理器
支持多个订阅源，每个订阅源可指定标签前缀
"""

import json
import yaml
import requests
import sys
import os
import time
import signal
from pathlib import Path
from typing import Optional, List, Dict

class ConfigManager:
    def __init__(self, config_file: str):
        self.config_file = Path(config_file)
        self.config = None
        self.subscription_sources = []
        self.update_interval = 3600
        self.running = True
        
    def load_config(self) -> dict:
        """加载配置文件"""
        with open(self.config_file, 'r', encoding='utf-8') as f:
            self.config = json.load(f)
        
        # 读取订阅配置（支持新旧格式）
        if '_subscription' in self.config:
            sub_config = self.config['_subscription']
            
            # 新格式：多订阅源
            if 'sources' in sub_config:
                for source in sub_config['sources']:
                    if source.get('enabled', True):
                        url = source.get('url', '')
                        # 支持环境变量
                        if url.startswith('env:'):
                            env_var = url.split(':', 1)[1]
                            url = os.environ.get(env_var, '')
                        
                        if url:
                            self.subscription_sources.append({
                                'url': url,
                                'tag_prefix': source.get('tag_prefix', ''),
                                'user_agent': sub_config.get('user_agent', 'clash')
                            })
            # 旧格式：单订阅 URL（兼容）
            elif 'url' in sub_config:
                url = sub_config['url']
                if url.startswith('env:'):
                    env_var = url.split(':', 1)[1]
                    url = os.environ.get(env_var, '')
                
                if url:
                    self.subscription_sources.append({
                        'url': url,
                        'tag_prefix': '',
                        'user_agent': sub_config.get('user_agent', 'clash')
                    })
            
            self.update_interval = sub_config.get('update_interval', 3600)
        
        return self.config
    
    def fetch_subscription(self, url: str, user_agent: str) -> Optional[dict]:
        """获取订阅内容"""
        try:
            print(f"正在获取订阅: {url[:50]}...")
            headers = {'User-Agent': user_agent}
            response = requests.get(url, headers=headers, timeout=30)
            response.raise_for_status()
            
            # 尝试解析为 YAML
            clash_config = yaml.safe_load(response.text)
            return clash_config
        except Exception as e:
            print(f"错误: 获取订阅失败: {e}")
            return None
    
    def convert_proxy(self, clash_proxy: dict, tag_prefix: str = '') -> Optional[dict]:
        """转换 Clash 代理为 sing-box 格式"""
        proxy_type = clash_proxy.get('type', '').lower()
        proxy_name = clash_proxy.get('name', 'proxy')
        
        # 添加标签前缀
        if tag_prefix:
            tag = f'🎉 {tag_prefix}🛺{proxy_name}'
        else:
            tag = f'🎉 {proxy_name}'
        
        singbox_proxy = {'tag': tag}
        
        if proxy_type == 'vmess':
            singbox_proxy['type'] = 'vmess'
            singbox_proxy['server'] = clash_proxy.get('server')
            singbox_proxy['server_port'] = clash_proxy.get('port')
            singbox_proxy['uuid'] = clash_proxy.get('uuid')
            singbox_proxy['alter_id'] = clash_proxy.get('alterId', 0)
            singbox_proxy['security'] = clash_proxy.get('cipher', 'auto')
            
            # TLS 配置
            if clash_proxy.get('tls'):
                singbox_proxy['tls'] = {
                    'enabled': True,
                    'server_name': clash_proxy.get('servername', clash_proxy.get('server'))
                }
                if clash_proxy.get('skip-cert-verify'):
                    singbox_proxy['tls']['insecure'] = True
            
            # 传输层配置
            if clash_proxy.get('network') == 'ws':
                singbox_proxy['transport'] = {
                    'type': 'ws',
                    'path': clash_proxy.get('ws-opts', {}).get('path', '/'),
                    'headers': clash_proxy.get('ws-opts', {}).get('headers', {})
                }
        
        elif proxy_type == 'trojan':
            singbox_proxy['type'] = 'trojan'
            singbox_proxy['server'] = clash_proxy.get('server')
            singbox_proxy['server_port'] = clash_proxy.get('port')
            singbox_proxy['password'] = clash_proxy.get('password')
            
            singbox_proxy['tls'] = {
                'enabled': True,
                'server_name': clash_proxy.get('sni', clash_proxy.get('server'))
            }
            if clash_proxy.get('skip-cert-verify'):
                singbox_proxy['tls']['insecure'] = True
        
        else:
            return None
        
        return singbox_proxy
    
    def update_proxies(self) -> bool:
        """更新所有订阅源的代理节点"""
        all_proxies = []
        
        # 从所有订阅源获取节点
        for source in self.subscription_sources:
            clash_config = self.fetch_subscription(source['url'], source['user_agent'])
            if not clash_config or 'proxies' not in clash_config:
                print(f"警告: 订阅源 {source['tag_prefix'] or 'default'} 获取失败")
                continue
            
            print(f"订阅源 [{source['tag_prefix'] or 'default'}] 找到 {len(clash_config['proxies'])} 个节点")
            
            # 转换节点
            for clash_proxy in clash_config['proxies']:
                singbox_proxy = self.convert_proxy(clash_proxy, source['tag_prefix'])
                if singbox_proxy:
                    all_proxies.append(singbox_proxy)
        
        if not all_proxies:
            print("错误: 没有可用的节点")
            return False
        
        print(f"共成功转换 {len(all_proxies)} 个节点")
        
        # 更新配置
        proxy_tags = [p['tag'] for p in all_proxies]
        
        # 移除旧节点，保留选择器
        new_outbounds = []
        for outbound in self.config['outbounds']:
            if outbound['type'] in ['selector', 'urltest', 'direct', 'block']:
                new_outbounds.append(outbound)
        
        # 添加新节点
        new_outbounds.extend(all_proxies)
        self.config['outbounds'] = new_outbounds
        
        # 更新代理组引用
        for outbound in self.config['outbounds']:
            if outbound['type'] in ['selector', 'urltest']:
                tag = outbound['tag']
                # 全部节点组：包含所有节点
                if tag == '🌐 全部节点':
                    outbound['outbounds'] = proxy_tags
                # 自动选择/故障转移/负载均衡：包含所有节点
                elif tag in ['♻️ 自动选择', '🔯 故障转移', '🔮 负载均衡-轮询', '🔮 负载均衡-散列']:
                    outbound['outbounds'] = proxy_tags
                # 特定前缀组：只包含对应前缀的节点
                elif tag.startswith('🎉 '):
                    # 提取前缀（如 "🎉 xiaonuo" -> "xiaonuo"）
                    prefix = tag.replace('🎉 ', '').replace('🛺', '')
                    matching_tags = [t for t in proxy_tags if f'🎉 {prefix}🛺' in t]
                    if matching_tags:
                        outbound['outbounds'] = matching_tags
        
        return True
    
    def save_runtime_config(self, output_file: str) -> bool:
        """保存运行时配置（移除元数据）"""
        runtime_config = self.config.copy()
        
        # 移除订阅配置元数据
        runtime_config.pop('_subscription', None)
        runtime_config.pop('_proxies_placeholder', None)
        runtime_config.pop('_comment', None)
        
        with open(output_file, 'w', encoding='utf-8') as f:
            json.dump(runtime_config, f, ensure_ascii=False, indent=2)
        
        print(f"✓ 配置已保存: {output_file}")
        return True
    
    def run_update_loop(self, output_file: str):
        """运行更新循环"""
        def signal_handler(sig, frame):
            print("\n收到停止信号，退出...")
            self.running = False
        
        signal.signal(signal.SIGINT, signal_handler)
        signal.signal(signal.SIGTERM, signal_handler)
        
        print(f"更新间隔: {self.update_interval} 秒")
        
        while self.running:
            if self.update_proxies():
                self.save_runtime_config(output_file)
                print(f"✓ 更新完成 ({time.strftime('%Y-%m-%d %H:%M:%S')})")
            else:
                print(f"✗ 更新失败 ({time.strftime('%Y-%m-%d %H:%M:%S')})")
            
            # 等待下次更新
            for _ in range(self.update_interval):
                if not self.running:
                    break
                time.sleep(1)

def main():
    if len(sys.argv) < 2:
        print("用法: python3 config_manager.py <配置文件> [输出文件] [模式]")
        print("")
        print("参数:")
        print("  配置文件  - 包含 _subscription 的配置模板")
        print("  输出文件  - 运行时配置输出路径（默认: runtime_config.json）")
        print("  模式      - once: 单次更新, daemon: 守护进程（默认: once）")
        print("")
        print("配置示例:")
        print('  "_subscription": {')
        print('    "sources": [')
        print('      {"url": "env:CLASH_SUBSCRIPTION_URL_1", "tag_prefix": "xiaonuo", "enabled": true},')
        print('      {"url": "env:CLASH_SUBSCRIPTION_URL_2", "tag_prefix": "airport2", "enabled": false}')
        print('    ]')
        print('  }')
        print("")
        print("环境变量:")
        print("  export CLASH_SUBSCRIPTION_URL_1='https://...'")
        print("  export CLASH_SUBSCRIPTION_URL_2='https://...'")
        print("")
        print("示例:")
        print("  python3 config_manager.py config.json runtime.json once")
        print("  python3 config_manager.py config.json runtime.json daemon")
        sys.exit(1)
    
    config_file = sys.argv[1]
    output_file = sys.argv[2] if len(sys.argv) > 2 else 'runtime_config.json'
    mode = sys.argv[3] if len(sys.argv) > 3 else 'once'
    
    manager = ConfigManager(config_file)
    manager.load_config()
    
    if not manager.subscription_sources:
        print("错误: 未配置订阅源或所有订阅源已禁用")
        sys.exit(1)
    
    if mode == 'daemon':
        print("运行模式: 守护进程")
        manager.run_update_loop(output_file)
    else:
        print("运行模式: 单次更新")
        if manager.update_proxies():
            manager.save_runtime_config(output_file)
            print("✓ 完成")
        else:
            print("✗ 失败")
            sys.exit(1)

if __name__ == '__main__':
    main()
