#!/usr/bin/env python3
"""
sing-box 订阅转换器（多格式支持）
自动识别订阅格式：Clash/Mihomo YAML、sing-box JSON、Base64/URI 分享链接
支持协议：shadowsocks, vmess, vless, trojan, hysteria2, tuic, anytls 等
"""

import json
import yaml
import requests
import sys
import os
import re
import base64
import time
import signal
from pathlib import Path
from typing import Optional, List, Dict, Tuple
from urllib.parse import urlsplit, parse_qs, unquote
from collections import defaultdict, Counter

# 区域匹配规则（原始节点名，不含前缀）
REGION_PATTERNS = {
    '🇹🇼 台湾': r'(?i)🇹🇼|台|tw|taiwan',
    '🇭🇰 香港': r'(?i)🇭🇰|港|hk|hongkong|hong kong',
    '🇯🇵 日本': r'(?i)🇯🇵|日|jp|japan',
    '🇸🇬 新加坡': r'(?i)🇸🇬|新|sg|singapore',
    '🇰🇷 韩国': r'(?i)🇰🇷|韩|kr|korea',
    '🇷🇺 俄罗斯': r'(?i)🇷🇺|俄|ru(?![a-z])|russia',
    '🇨🇦 加拿大': r'(?i)🇨🇦|加|ca(?![a-z])|canada',
    '🇺🇸 美国': r'(?i)🇺🇸|美|us(?![a-z])|usa|united states',
    '🇬🇧 英国': r'(?i)🇬🇧|英|uk(?![a-z])|britain|united kingdom',
    '🇫🇷 法国': r'(?i)🇫🇷|法|fr(?![a-z])|france',
    '🇩🇪 德国': r'(?i)🇩🇪|德|de(?![a-z])|germany',
    '🇧🇷 巴西': r'(?i)🇧🇷|巴西|br(?![a-z])|brazil',
    '🇳🇱 荷兰': r'(?i)🇳🇱|荷|nl(?![a-z])|netherlands',
}

# 信息节点过滤（流量、到期等无效节点）
INFO_NODE_PATTERN = r'(?i)剩余|流量|到期|过期|官网|套餐|重置|expire|traffic|reset|website'

# 排除节点（公司、直连等）
EXCLUDE_PATTERN = r'(?i)公司|直连|广告|拦截|company|direct'

class ConfigManager:
    def __init__(self, config_file: str):
        self.config_file = Path(config_file)
        self.config = None
        self.subscription_sources = []
        self.update_interval = 3600
        self.running = True
        
    def load_config(self) -> dict:
        """加载配置模板"""
        with open(self.config_file, 'r', encoding='utf-8') as f:
            self.config = json.load(f)
        
        # 从环境变量读取订阅源（优先级最高）
        sources = self._load_sources_from_env()
        
        if sources:
            print(f"提示: 使用环境变量订阅配置（共 {len(sources)} 个订阅源）")
            self.subscription_sources = sources
        else:
            print("错误: 未找到 SUBSCRIPTION_URL 或 SUBSCRIPTION_URL_N 环境变量")
            sys.exit(1)
        
        # 检查旧的 CLASH_SUBSCRIPTION_* 变量
        old_vars = [k for k in os.environ if k.startswith('CLASH_SUBSCRIPTION_')]
        if old_vars:
            print(f"⚠️ 检测到旧的环境变量命名: {', '.join(old_vars[:3])}")
            print("   请改用 SUBSCRIPTION_URL_N, SUBSCRIPTION_TAG_N, SUBSCRIPTION_ENABLED_N")
        
        # 应用环境变量覆盖（inbounds / clash_api / api service / routing_mark）
        self._apply_env_overrides()
        
        return self.config
    
    def _apply_env_overrides(self):
        """根据环境变量覆盖模板中的入站端口、监听地址、Clash API、API 服务及 routing_mark"""
        self._override_inbounds()
        self._override_clash_api()
        self._override_api_service()
        self._override_routing_mark()
    
    def _override_inbounds(self):
        """覆盖入站监听地址和端口
        
        支持的环境变量（按入站 type 匹配）：
          MIXED_LISTEN / MIXED_PORT          -> type=mixed 入站
          SOCKS_LISTEN / SOCKS_PORT          -> type=socks 入站
          TPROXY_LISTEN / TPROXY_PORT        -> type=tproxy 入站
        """
        inbounds = self.config.get('inbounds')
        if not isinstance(inbounds, list):
            return
        
        # type -> 环境变量前缀
        prefix_map = {
            'mixed': 'MIXED',
            'socks': 'SOCKS',
            'tproxy': 'TPROXY',
        }
        
        for inbound in inbounds:
            itype = inbound.get('type')
            prefix = prefix_map.get(itype)
            if not prefix:
                continue
            
            listen = os.environ.get(f'{prefix}_LISTEN', '').strip()
            if listen:
                inbound['listen'] = listen
                print(f"  覆盖入站 [{itype}] 监听地址: {listen}")
            
            port = os.environ.get(f'{prefix}_PORT', '').strip()
            if port:
                try:
                    inbound['listen_port'] = int(port)
                    print(f"  覆盖入站 [{itype}] 端口: {port}")
                except ValueError:
                    print(f"  ⚠️ 入站 [{itype}] 端口值无效，已忽略: {port}")
    
    def _override_clash_api(self):
        """覆盖 experimental.clash_api 的 external_controller 和 secret
        
        支持的环境变量：
          CLASH_API_EXTERNAL_CONTROLLER   -> external_controller 监听地址（如 0.0.0.0:9090）
          CLASH_API_SECRET                -> secret 访问密码
        """
        controller = os.environ.get('CLASH_API_EXTERNAL_CONTROLLER', '').strip()
        secret = os.environ.get('CLASH_API_SECRET', '').strip()
        
        if not controller and not secret:
            return
        
        experimental = self.config.setdefault('experimental', {})
        clash_api = experimental.setdefault('clash_api', {})
        
        if controller:
            clash_api['external_controller'] = controller
            print(f"  覆盖 clash_api external_controller: {controller}")
        if secret:
            clash_api['secret'] = secret
            print("  覆盖 clash_api secret: ******")
    
    def _override_api_service(self):
        """覆盖 services 中 type=api 服务的 listen / listen_port / secret
        
        支持的环境变量：
          API_SERVICE_LISTEN   -> 监听地址
          API_SERVICE_PORT     -> 监听端口
          API_SERVICE_SECRET   -> 访问密码
        """
        listen = os.environ.get('API_SERVICE_LISTEN', '').strip()
        port = os.environ.get('API_SERVICE_PORT', '').strip()
        secret = os.environ.get('API_SERVICE_SECRET', '').strip()
        
        if not listen and not port and not secret:
            return
        
        services = self.config.get('services')
        if not isinstance(services, list):
            return
        
        for service in services:
            if service.get('type') != 'api':
                continue
            
            if listen:
                service['listen'] = listen
                print(f"  覆盖 api 服务监听地址: {listen}")
            if port:
                try:
                    service['listen_port'] = int(port)
                    print(f"  覆盖 api 服务端口: {port}")
                except ValueError:
                    print(f"  ⚠️ api 服务端口值无效，已忽略: {port}")
            if secret:
                service['secret'] = secret
                print("  覆盖 api 服务 secret: ******")
    
    def _override_routing_mark(self):
        """覆盖出站的 routing_mark
        
        支持的环境变量：
          ROUTING_MARK   -> 作用于所有已含 routing_mark 字段的出站
        """
        mark = os.environ.get('ROUTING_MARK', '').strip()
        if not mark:
            return
        
        try:
            mark_val = int(mark)
        except ValueError:
            print(f"  ⚠️ ROUTING_MARK 值无效，已忽略: {mark}")
            return
        
        outbounds = self.config.get('outbounds')
        if not isinstance(outbounds, list):
            return
        
        for outbound in outbounds:
            if 'routing_mark' in outbound:
                outbound['routing_mark'] = mark_val
                print(f"  覆盖出站 [{outbound.get('tag')}] routing_mark: {mark_val}")
    
    def _load_sources_from_env(self) -> List[Dict]:
        """从环境变量加载订阅源"""
        sources = []
        seen_tags = set()
        
        # 检查基础 URL (SUBSCRIPTION_URL)
        base_url = os.environ.get('SUBSCRIPTION_URL', '').strip()
        if base_url:
            tag = os.environ.get('SUBSCRIPTION_TAG', 'default').strip()
            enabled_str = os.environ.get('SUBSCRIPTION_ENABLED', 'true').strip()
            enabled = enabled_str.lower() in ['true', '1', 'yes', 'on']
            ua = os.environ.get('SUBSCRIPTION_UA', 'clash.meta').strip()
            
            if enabled:
                if tag in seen_tags:
                    tag = f"{tag}_{len([s for s in sources if s['tag'].startswith(tag)])+1}"
                seen_tags.add(tag)
                sources.append({'url': base_url, 'tag': tag, 'user_agent': ua})
        
        # 检查编号 URL (SUBSCRIPTION_URL_1, _2, _3 等)
        for i in range(1, 100):
            url = os.environ.get(f'SUBSCRIPTION_URL_{i}', '').strip()
            if not url:
                if i > 5 and all(not os.environ.get(f'SUBSCRIPTION_URL_{j}', '').strip() for j in range(i-4, i)):
                    break
                continue
            
            tag = os.environ.get(f'SUBSCRIPTION_TAG_{i}', f'airport{i}').strip()
            enabled_str = os.environ.get(f'SUBSCRIPTION_ENABLED_{i}', 'true').strip()
            enabled = enabled_str.lower() in ['true', '1', 'yes', 'on']
            ua = os.environ.get(f'SUBSCRIPTION_UA_{i}', 'clash.meta').strip()
            
            if enabled:
                if tag in seen_tags:
                    tag = f"{tag}_{len([s for s in sources if s['tag'].startswith(tag)])+1}"
                seen_tags.add(tag)
                sources.append({'url': url, 'tag': tag, 'user_agent': ua})
        
        return sources
    
    def fetch_subscription(self, url: str, user_agent: str) -> str:
        """获取订阅内容"""
        from urllib.parse import urlsplit
        parts = urlsplit(url)
        print(f"正在获取订阅: {parts.scheme}://{parts.netloc}/...")
        
        headers = {'User-Agent': user_agent}
        response = requests.get(url, headers=headers, timeout=30)
        response.raise_for_status()
        return response.text
    
    def detect_format(self, content: str) -> str:
        """检测订阅格式"""
        content = content.strip().lstrip('\ufeff')
        
        # sing-box JSON
        if content.startswith('{'):
            try:
                data = json.loads(content)
                if isinstance(data, dict) and 'outbounds' in data:
                    return 'singbox-json'
            except:
                pass
        
        # Clash YAML
        try:
            data = yaml.safe_load(content)
            if isinstance(data, dict) and 'proxies' in data:
                return 'clash-yaml'
        except:
            pass
        
        # URI 列表（base64 或纯文本）
        if '://' in content:
            return 'uri-list'
        
        # 尝试 base64 解码
        try:
            pad = content + '=' * (-len(content) % 4)
            decoded = base64.b64decode(pad.replace('-', '+').replace('_', '/'), validate=True).decode('utf-8', errors='ignore')
            if '://' in decoded:
                return 'uri-base64'
        except:
            pass
        
        return 'unknown'
    
    def parse_subscription(self, content: str, fmt: str, tag: str) -> List[Dict]:
        """解析订阅内容为 sing-box outbounds"""
        if fmt == 'singbox-json':
            return self._parse_singbox_json(content, tag)
        elif fmt == 'clash-yaml':
            return self._parse_clash_yaml(content, tag)
        elif fmt in ('uri-list', 'uri-base64'):
            if fmt == 'uri-base64':
                pad = content + '=' * (-len(content) % 4)
                content = base64.b64decode(pad.replace('-', '+').replace('_', '/'), validate=True).decode('utf-8', errors='ignore')
            return self._parse_uri_list(content, tag)
        else:
            raise ValueError(f"未知格式: {fmt}")
    
    def _parse_singbox_json(self, content: str, tag_prefix: str) -> List[Dict]:
        """解析 sing-box JSON 格式"""
        data = json.loads(content)
        outbounds = []
        proxy_types = {'shadowsocks', 'vmess', 'vless', 'trojan', 'hysteria', 'hysteria2', 'tuic', 'ssh', 'socks', 'http'}
        
        for ob in data.get('outbounds', []):
            if ob.get('type') not in proxy_types:
                continue
            
            # 清理不兼容字段
            ob = {k: v for k, v in ob.items() if k not in ('detour', 'domain_strategy', 'domain_resolver')}
            
            # 添加标签前缀
            name = ob.get('tag', ob.get('server', 'node'))
            ob['tag'] = f'🎉 [{tag_prefix}] {name}'
            outbounds.append(ob)
        
        return outbounds
    
    def _parse_clash_yaml(self, content: str, tag_prefix: str) -> List[Dict]:
        """解析 Clash YAML 格式"""
        data = yaml.safe_load(content)
        proxies = data.get('proxies', [])
        
        if not proxies:
            print(f"警告: 订阅源 {tag_prefix} 无 proxies 字段")
            return []
        
        outbounds = []
        skip_counts = Counter()
        
        for proxy in proxies:
            try:
                ob = self._convert_clash_proxy(proxy)
                if ob:
                    name = proxy.get('name', 'node')
                    # 过滤信息节点
                    if re.search(INFO_NODE_PATTERN, name):
                        skip_counts['info'] += 1
                        continue
                    
                    ob['tag'] = f'🎉 [{tag_prefix}] {name}'
                    outbounds.append(ob)
                else:
                    skip_counts[proxy.get('type', 'unknown')] += 1
            except Exception as e:
                skip_counts['error'] += 1
        
        if skip_counts:
            print(f"  跳过: {dict(skip_counts)}")
        
        return outbounds
    
    def _parse_uri_list(self, content: str, tag_prefix: str) -> List[Dict]:
        """解析 URI 分享链接列表"""
        outbounds = []
        skip_counts = Counter()
        
        for line in content.splitlines():
            line = line.strip()
            if not line or not '://' in line:
                continue
            
            try:
                scheme = line.split('://')[0].lower()
                if scheme in ('vmess', 'vless', 'trojan', 'ss', 'hysteria2', 'hy2', 'tuic', 'anytls', 'hysteria'):
                    proxy_dict = self._parse_uri(line)
                    if proxy_dict:
                        ob = self._convert_clash_proxy(proxy_dict)
                        if ob:
                            name = proxy_dict.get('name', 'node')
                            if re.search(INFO_NODE_PATTERN, name):
                                skip_counts['info'] += 1
                                continue
                            
                            ob['tag'] = f'🎉 [{tag_prefix}] {name}'
                            outbounds.append(ob)
                        else:
                            skip_counts[scheme] += 1
            except Exception as e:
                skip_counts['error'] += 1
        
        if skip_counts:
            print(f"  跳过: {dict(skip_counts)}")
        
        return outbounds
    
    def _parse_uri(self, uri: str) -> Optional[Dict]:
        """解析各类 URI 为 Clash 格式字典"""
        scheme = uri.split('://')[0].lower()
        
        if scheme == 'vmess':
            return self._parse_vmess_uri(uri)
        elif scheme == 'vless':
            return self._parse_vless_uri(uri)
        elif scheme == 'trojan':
            return self._parse_trojan_uri(uri)
        elif scheme == 'ss':
            return self._parse_ss_uri(uri)
        elif scheme in ('hysteria2', 'hy2'):
            return self._parse_hysteria2_uri(uri)
        elif scheme == 'tuic':
            return self._parse_tuic_uri(uri)
        elif scheme == 'anytls':
            return self._parse_anytls_uri(uri)
        elif scheme == 'hysteria':
            return self._parse_hysteria_uri(uri)
        
        return None
    
    def _parse_vmess_uri(self, uri: str) -> Optional[Dict]:
        """解析 vmess:// URI"""
        body = uri.split('://')[1]
        pad = body + '=' * (-len(body) % 4)
        data = json.loads(base64.b64decode(pad).decode('utf-8'))
        
        proxy = {
            'type': 'vmess',
            'name': data.get('ps', 'vmess'),
            'server': data.get('add', ''),
            'port': int(data.get('port', 443)),
            'uuid': data.get('id', ''),
            'alterId': int(data.get('aid', 0)),
            'cipher': data.get('scy', 'auto'),
            'network': data.get('net', 'tcp'),
        }
        
        if data.get('tls') == 'tls':
            proxy['tls'] = True
            proxy['servername'] = data.get('sni') or data.get('host') or proxy['server']
            if data.get('fp'):
                proxy['client-fingerprint'] = data.get('fp')
        
        net = proxy['network']
        if net == 'ws':
            proxy['ws-opts'] = {
                'path': data.get('path', '/'),
                'headers': {'Host': data.get('host', proxy['server'])}
            }
        elif net == 'grpc':
            proxy['grpc-opts'] = {'grpc-service-name': data.get('path', '')}
        elif net == 'h2':
            proxy['h2-opts'] = {
                'host': [data.get('host', proxy['server'])],
                'path': data.get('path', '/')
            }
        
        return proxy
    
    def _parse_vless_uri(self, uri: str) -> Optional[Dict]:
        """解析 vless:// URI"""
        parts = urlsplit(uri)
        query = parse_qs(parts.query)
        
        proxy = {
            'type': 'vless',
            'name': unquote(parts.fragment) if parts.fragment else 'vless',
            'server': parts.hostname,
            'port': parts.port or 443,
            'uuid': parts.username,
            'encryption': query.get('encryption', ['none'])[0],
        }
        
        flow = query.get('flow', [''])[0]
        if flow:
            proxy['flow'] = flow
        
        security = query.get('security', [''])[0]
        if security in ('tls', 'reality'):
            proxy['tls'] = True
            sni = query.get('sni', [''])[0]
            if sni:
                proxy['servername'] = sni
            fp = query.get('fp', [''])[0]
            if fp:
                proxy['client-fingerprint'] = fp
            
            if security == 'reality':
                proxy['reality-opts'] = {}
                pbk = query.get('pbk', [''])[0]
                if pbk:
                    proxy['reality-opts']['public-key'] = pbk
                sid = query.get('sid', [''])[0]
                if sid:
                    proxy['reality-opts']['short-id'] = sid
        
        net = query.get('type', ['tcp'])[0]
        proxy['network'] = net
        
        if net == 'ws':
            proxy['ws-opts'] = {
                'path': query.get('path', ['/'])[0],
                'headers': {'Host': query.get('host', [proxy['server']])[0]}
            }
        elif net == 'grpc':
            proxy['grpc-opts'] = {'grpc-service-name': query.get('serviceName', [''])[0]}
        
        return proxy
    
    def _parse_trojan_uri(self, uri: str) -> Optional[Dict]:
        """解析 trojan:// URI"""
        parts = urlsplit(uri)
        query = parse_qs(parts.query)
        
        proxy = {
            'type': 'trojan',
            'name': unquote(parts.fragment) if parts.fragment else 'trojan',
            'server': parts.hostname,
            'port': parts.port or 443,
            'password': unquote(parts.username) if parts.username else '',
        }
        
        security = query.get('security', ['tls'])[0]
        if security != 'none':
            proxy['sni'] = query.get('sni', [proxy['server']])[0]
        
        net = query.get('type', ['tcp'])[0]
        if net != 'tcp':
            proxy['network'] = net
            if net == 'ws':
                proxy['ws-opts'] = {
                    'path': query.get('path', ['/'])[0],
                    'headers': {'Host': query.get('host', [proxy['server']])[0]}
                }
        
        return proxy
    
    def _parse_ss_uri(self, uri: str) -> Optional[Dict]:
        """解析 ss:// URI"""
        body = uri.split('://')[1]
        if '@' in body:
            userinfo, rest = body.split('@', 1)
        else:
            rest = body
            userinfo = ''
        
        # 尝试 base64 解码
        try:
            pad = userinfo + '=' * (-len(userinfo) % 4)
            decoded = base64.b64decode(pad).decode('utf-8')
            if ':' in decoded:
                method, password = decoded.split(':', 1)
            else:
                method, password = 'aes-128-gcm', ''
        except:
            if ':' in userinfo:
                method, password = userinfo.split(':', 1)
            else:
                method, password = 'aes-128-gcm', ''
        
        if '#' in rest:
            netloc, name = rest.split('#', 1)
            name = unquote(name)
        else:
            netloc, name = rest, 'ss'
        
        if ':' in netloc:
            server, port = netloc.rsplit(':', 1)
            port = int(port.split('?')[0])
        else:
            server, port = netloc, 8388
        
        proxy = {
            'type': 'ss',
            'name': name,
            'server': server.strip('[]'),
            'port': port,
            'cipher': method,
            'password': password,
        }
        
        return proxy
    
    def _parse_hysteria2_uri(self, uri: str) -> Optional[Dict]:
        """解析 hysteria2:// URI"""
        parts = urlsplit(uri)
        query = parse_qs(parts.query)
        
        proxy = {
            'type': 'hysteria2',
            'name': unquote(parts.fragment) if parts.fragment else 'hy2',
            'server': parts.hostname,
            'port': parts.port or 443,
            'password': unquote(parts.username) if parts.username else '',
        }
        
        if query.get('sni'):
            proxy['sni'] = query['sni'][0]
        if query.get('insecure', [''])[0] == '1':
            proxy['skip-cert-verify'] = True
        if query.get('obfs'):
            proxy['obfs'] = query['obfs'][0]
        if query.get('obfs-password'):
            proxy['obfs-password'] = query['obfs-password'][0]
        
        return proxy
    
    def _parse_tuic_uri(self, uri: str) -> Optional[Dict]:
        """解析 tuic:// URI"""
        parts = urlsplit(uri)
        query = parse_qs(parts.query)
        
        uuid, password = '', ''
        if parts.username:
            if ':' in parts.username:
                uuid, password = parts.username.split(':', 1)
            else:
                uuid = parts.username
        
        proxy = {
            'type': 'tuic',
            'name': unquote(parts.fragment) if parts.fragment else 'tuic',
            'server': parts.hostname,
            'port': parts.port or 443,
            'uuid': unquote(uuid),
            'password': unquote(password),
        }
        
        if query.get('sni'):
            proxy['sni'] = query['sni'][0]
        if query.get('congestion_control'):
            proxy['congestion-controller'] = query['congestion_control'][0]
        
        return proxy
    
    def _parse_anytls_uri(self, uri: str) -> Optional[Dict]:
        """解析 anytls:// URI"""
        parts = urlsplit(uri)
        query = parse_qs(parts.query)
        
        proxy = {
            'type': 'anytls',
            'name': unquote(parts.fragment) if parts.fragment else 'anytls',
            'server': parts.hostname,
            'port': parts.port or 443,
            'password': unquote(parts.username) if parts.username else '',
        }
        
        if query.get('sni'):
            proxy['sni'] = query['sni'][0]
        if query.get('insecure', [''])[0] == '1':
            proxy['skip-cert-verify'] = True
        
        return proxy
    
    def _parse_hysteria_uri(self, uri: str) -> Optional[Dict]:
        """解析 hysteria:// URI (v1)"""
        parts = urlsplit(uri)
        query = parse_qs(parts.query)
        
        proxy = {
            'type': 'hysteria',
            'name': unquote(parts.fragment) if parts.fragment else 'hysteria',
            'server': parts.hostname,
            'port': parts.port or 443,
        }
        
        if query.get('auth'):
            proxy['auth_str'] = query['auth'][0]
        if query.get('peer'):
            proxy['sni'] = query['peer'][0]
        if query.get('insecure', [''])[0] == '1':
            proxy['skip-cert-verify'] = True
        
        return proxy
    
    def _convert_clash_proxy(self, proxy: dict) -> Optional[Dict]:
        """Clash 代理转 sing-box outbound"""
        ptype = proxy.get('type', '').lower()
        
        if ptype == 'ss':
            return self._convert_ss(proxy)
        elif ptype == 'vmess':
            return self._convert_vmess(proxy)
        elif ptype == 'vless':
            return self._convert_vless(proxy)
        elif ptype == 'trojan':
            return self._convert_trojan(proxy)
        elif ptype == 'hysteria2':
            return self._convert_hysteria2(proxy)
        elif ptype == 'hysteria':
            return self._convert_hysteria(proxy)
        elif ptype == 'tuic':
            return self._convert_tuic(proxy)
        elif ptype == 'anytls':
            return self._convert_anytls(proxy)
        elif ptype == 'socks5':
            return self._convert_socks(proxy)
        elif ptype == 'http':
            return self._convert_http(proxy)
        
        return None
    
    def _convert_ss(self, proxy: dict) -> Dict:
        """shadowsocks"""
        ob = {
            'type': 'shadowsocks',
            'server': proxy['server'],
            'server_port': proxy['port'],
            'method': proxy.get('cipher', 'aes-128-gcm'),
            'password': proxy['password'],
        }
        
        plugin = proxy.get('plugin')
        if plugin:
            ob['plugin'] = plugin
            ob['plugin_opts'] = proxy.get('plugin-opts', '')
        
        return ob
    
    def _convert_vmess(self, proxy: dict) -> Dict:
        """vmess"""
        ob = {
            'type': 'vmess',
            'server': proxy['server'],
            'server_port': proxy['port'],
            'uuid': proxy['uuid'],
            'alter_id': proxy.get('alterId', 0),
            'security': proxy.get('cipher', 'auto'),
        }
        
        # TLS
        if proxy.get('tls'):
            tls = self._build_tls(proxy, False)
            if tls:
                ob['tls'] = tls
        
        # Transport
        transport = self._build_transport(proxy)
        if transport:
            ob['transport'] = transport
        
        return ob
    
    def _convert_vless(self, proxy: dict) -> Dict:
        """vless"""
        ob = {
            'type': 'vless',
            'server': proxy['server'],
            'server_port': proxy['port'],
            'uuid': proxy['uuid'],
        }
        
        flow = proxy.get('flow')
        if flow:
            ob['flow'] = flow
        
        # TLS / Reality
        tls = self._build_tls(proxy, True)
        if tls:
            ob['tls'] = tls
        
        # Transport
        transport = self._build_transport(proxy)
        if transport:
            ob['transport'] = transport
        
        return ob
    
    def _convert_trojan(self, proxy: dict) -> Dict:
        """trojan"""
        ob = {
            'type': 'trojan',
            'server': proxy['server'],
            'server_port': proxy['port'],
            'password': proxy['password'],
        }
        
        # TLS (默认启用)
        tls = self._build_tls(proxy, False)
        if tls:
            ob['tls'] = tls
        
        # Transport
        transport = self._build_transport(proxy)
        if transport:
            ob['transport'] = transport
        
        return ob
    
    def _convert_hysteria2(self, proxy: dict) -> Dict:
        """hysteria2"""
        ob = {
            'type': 'hysteria2',
            'server': proxy['server'],
            'server_port': proxy['port'],
            'password': proxy.get('password', ''),
        }
        
        if proxy.get('up'):
            ob['up_mbps'] = self._parse_bandwidth(proxy['up'])
        if proxy.get('down'):
            ob['down_mbps'] = self._parse_bandwidth(proxy['down'])
        
        if proxy.get('obfs'):
            ob['obfs'] = {'type': 'salamander', 'password': proxy.get('obfs-password', '')}
        
        tls = {'enabled': True}
        if proxy.get('sni'):
            tls['server_name'] = proxy['sni']
        if proxy.get('skip-cert-verify'):
            tls['insecure'] = True
        ob['tls'] = tls
        
        return ob
    
    def _convert_hysteria(self, proxy: dict) -> Dict:
        """hysteria v1"""
        ob = {
            'type': 'hysteria',
            'server': proxy['server'],
            'server_port': proxy['port'],
        }
        
        if proxy.get('auth_str'):
            ob['auth_str'] = proxy['auth_str']
        
        if proxy.get('up'):
            ob['up_mbps'] = self._parse_bandwidth(proxy['up'])
        if proxy.get('down'):
            ob['down_mbps'] = self._parse_bandwidth(proxy['down'])
        
        tls = {'enabled': True}
        if proxy.get('sni'):
            tls['server_name'] = proxy['sni']
        if proxy.get('skip-cert-verify'):
            tls['insecure'] = True
        ob['tls'] = tls
        
        return ob
    
    def _convert_tuic(self, proxy: dict) -> Dict:
        """tuic"""
        ob = {
            'type': 'tuic',
            'server': proxy['server'],
            'server_port': proxy['port'],
            'uuid': proxy['uuid'],
            'password': proxy.get('password', ''),
        }
        
        if proxy.get('congestion-controller'):
            ob['congestion_control'] = proxy['congestion-controller']
        
        tls = {'enabled': True}
        if proxy.get('sni'):
            tls['server_name'] = proxy['sni']
        if proxy.get('skip-cert-verify'):
            tls['insecure'] = True
        ob['tls'] = tls
        
        return ob
    
    def _convert_anytls(self, proxy: dict) -> Dict:
        """anytls -> shadowtls v3"""
        tls = {'enabled': True}
        
        if proxy.get('sni'):
            tls['server_name'] = proxy['sni']
        else:
            tls['server_name'] = proxy['server']
        
        if proxy.get('skip-cert-verify'):
            tls['insecure'] = True
        
        ob = {
            'type': 'shadowtls',
            'server': proxy['server'],
            'server_port': proxy['port'],
            'version': 3,
            'password': proxy.get('password', ''),
            'tls': tls,
        }
        
        return ob
    
    def _convert_socks(self, proxy: dict) -> Dict:
        """socks5"""
        ob = {
            'type': 'socks',
            'server': proxy['server'],
            'server_port': proxy['port'],
        }
        
        if proxy.get('username'):
            ob['username'] = proxy['username']
            ob['password'] = proxy.get('password', '')
        
        return ob
    
    def _convert_http(self, proxy: dict) -> Dict:
        """http"""
        ob = {
            'type': 'http',
            'server': proxy['server'],
            'server_port': proxy['port'],
        }
        
        if proxy.get('username'):
            ob['username'] = proxy['username']
            ob['password'] = proxy.get('password', '')
        
        return ob
    
    def _build_tls(self, proxy: dict, is_vless: bool) -> Optional[Dict]:
        """构建 TLS 配置"""
        tls_enabled = proxy.get('tls', False)
        has_reality = 'reality-opts' in proxy
        
        if not tls_enabled and not has_reality:
            return None
        
        tls = {'enabled': True}
        
        # server_name
        sni = proxy.get('servername') or proxy.get('sni')
        if not sni and proxy.get('ws-opts'):
            sni = proxy['ws-opts'].get('headers', {}).get('Host')
        if not sni:
            sni = proxy.get('server')
        if sni:
            tls['server_name'] = sni
        
        # insecure
        if proxy.get('skip-cert-verify'):
            tls['insecure'] = True
        
        # alpn
        alpn = proxy.get('alpn')
        if alpn:
            tls['alpn'] = alpn if isinstance(alpn, list) else [alpn]
        
        # reality
        if has_reality:
            reality_opts = proxy['reality-opts']
            tls['reality'] = {
                'enabled': True,
                'public_key': reality_opts.get('public-key', ''),
                'short_id': str(reality_opts.get('short-id', '')),
            }
            # reality 强制 utls
            if not proxy.get('client-fingerprint'):
                tls['utls'] = {'enabled': True, 'fingerprint': 'chrome'}
        
        # utls
        fp = proxy.get('client-fingerprint')
        if fp and tls_enabled:
            tls['utls'] = {'enabled': True, 'fingerprint': fp}
        
        return tls
    
    def _build_transport(self, proxy: dict) -> Optional[Dict]:
        """构建 transport 配置"""
        net = proxy.get('network', 'tcp')
        
        if net == 'ws':
            ws_opts = proxy.get('ws-opts', {})
            path = ws_opts.get('path', '/')
            
            # 处理 early-data (?ed=2048)
            max_early_data = 0
            if '?ed=' in path:
                path, query = path.split('?', 1)
                for part in query.split('&'):
                    if part.startswith('ed='):
                        try:
                            max_early_data = int(part.split('=')[1])
                        except:
                            pass
            
            transport = {
                'type': 'ws',
                'path': path,
                'headers': ws_opts.get('headers', {}),
            }
            
            if max_early_data > 0:
                transport['max_early_data'] = max_early_data
                transport['early_data_header_name'] = 'Sec-WebSocket-Protocol'
            
            return transport
        
        elif net == 'grpc':
            grpc_opts = proxy.get('grpc-opts', {})
            return {
                'type': 'grpc',
                'service_name': grpc_opts.get('grpc-service-name', ''),
            }
        
        elif net == 'h2':
            h2_opts = proxy.get('h2-opts', {})
            return {
                'type': 'http',
                'host': h2_opts.get('host', []),
                'path': h2_opts.get('path', '/'),
            }
        
        elif net == 'httpupgrade':
            http_opts = proxy.get('http-opts', {}) or proxy.get('ws-opts', {})
            return {
                'type': 'httpupgrade',
                'path': http_opts.get('path', '/'),
                'host': http_opts.get('headers', {}).get('Host', ''),
            }
        
        return None
    
    def _parse_bandwidth(self, bw: str) -> int:
        """解析带宽值 (如 "100 Mbps" -> 100)"""
        if isinstance(bw, (int, float)):
            return int(bw)
        
        bw = str(bw).strip().lower()
        match = re.match(r'(\d+(?:\.\d+)?)\s*(mbps|kb|mb|gb)?', bw)
        if match:
            val = float(match.group(1))
            unit = match.group(2) or ''
            if 'gb' in unit:
                return int(val * 1024)
            elif 'kb' in unit:
                return int(val / 1024)
            else:
                return int(val)
        return 0
    
    def update_proxies(self) -> bool:
        """更新代理节点"""
        all_proxies = []
        source_tags = []
        
        for source in self.subscription_sources:
            tag = source['tag']
            url = source['url']
            ua = source['user_agent']
            
            try:
                content = self.fetch_subscription(url, ua)
                fmt = self.detect_format(content)
                print(f"  格式: {fmt}")
                
                proxies = self.parse_subscription(content, fmt, tag)
                print(f"  订阅源 [{tag}] 找到 {len(proxies)} 个节点")
                
                if proxies:
                    all_proxies.extend(proxies)
                    source_tags.append(tag)
            except Exception as e:
                print(f"  警告: 订阅源 {tag} 获取失败: {e}")
        
        if not all_proxies:
            print("错误: 没有可用的节点")
            return False
        
        # 去重
        seen = set()
        unique_proxies = []
        for p in all_proxies:
            tag = p['tag']
            if tag in seen:
                suffix = 2
                while f"{tag} #{suffix}" in seen:
                    suffix += 1
                p['tag'] = f"{tag} #{suffix}"
            seen.add(p['tag'])
            unique_proxies.append(p)
        
        print(f"共成功转换 {len(unique_proxies)} 个节点")
        
        # 重建配置
        self._rebuild_config(unique_proxies, source_tags)
        return True
    
    def _rebuild_config(self, proxies: List[Dict], source_tags: List[str]):
        """重建配置文件"""
        # 移除旧的 proxy 节点，保留 selector/urltest/direct/block
        old_outbounds = self.config.get('outbounds', [])
        keep_types = {'selector', 'urltest', 'direct', 'block', 'dns'}
        
        # 移除旧的订阅源分组（🎉 开头）
        new_outbounds = [ob for ob in old_outbounds 
                        if ob.get('type') in keep_types 
                        and not (ob.get('tag', '').startswith('🎉 ') and ob.get('type') in ('selector', 'urltest'))]
        
        # 添加新节点
        new_outbounds.extend(proxies)
        
        # 构建区域分组
        region_map = self._build_region_map(proxies)
        
        # 构建订阅源分组映射
        source_map = self._build_source_map(proxies, source_tags)
        
        # 从模板中获取 urltest 默认配置
        template_urltest = next((ob for ob in old_outbounds if ob.get('type') == 'urltest'), {})
        test_url = template_urltest.get('url', 'https://www.apple.com/library/test/success.html')
        test_interval = template_urltest.get('interval', '30s')
        test_tolerance = template_urltest.get('tolerance', 10)
        
        # 创建订阅源分组并插入到 direct 后面
        direct_idx = next((i for i, ob in enumerate(new_outbounds) if ob.get('tag') == '🎯 全球直连'), 0)
        insert_idx = direct_idx + 1
        
        for stag in source_tags:
            urltest_tag = f'🎉 {stag}🛺'
            selector_tag = f'🎉 {stag}'
            
            if urltest_tag in source_map:
                # urltest 组
                new_outbounds.insert(insert_idx, {
                    'type': 'urltest',
                    'tag': urltest_tag,
                    'outbounds': source_map[urltest_tag],
                    'url': test_url,
                    'interval': test_interval,
                    'tolerance': test_tolerance,
                })
                insert_idx += 1
                
                # selector 组
                new_outbounds.insert(insert_idx, {
                    'type': 'selector',
                    'tag': selector_tag,
                    'outbounds': source_map[selector_tag],
                })
                insert_idx += 1
        
        # 重建其他分组的引用
        for ob in new_outbounds:
            if ob['type'] in ('selector', 'urltest') and not ob.get('tag', '').startswith('🎉 '):
                self._rebuild_outbound_refs(ob, region_map, source_map, proxies)
        
        # 移除空分组
        new_outbounds = [ob for ob in new_outbounds if self._is_group_valid(ob, proxies)]
        
        self.config['outbounds'] = new_outbounds
    
    def _build_region_map(self, proxies: List[Dict]) -> Dict[str, List[str]]:
        """构建区域 -> 节点标签映射"""
        region_map = defaultdict(list)
        matched_tags = set()
        
        for proxy in proxies:
            tag = proxy['tag']
            # 提取原始节点名（去除前缀）
            name_match = re.search(r'\] (.+)$', tag)
            orig_name = name_match.group(1) if name_match else tag
            
            # 检查是否匹配排除模式
            if re.search(EXCLUDE_PATTERN, orig_name):
                continue
            
            # 匹配区域
            matched = False
            for region, pattern in REGION_PATTERNS.items():
                if re.search(pattern, orig_name):
                    region_map[region].append(tag)
                    # 同步填充自动测速组（🛺 变体），与手动选择组节点一致
                    region_map[f'{region}🛺'].append(tag)
                    matched = True
            
            if matched:
                matched_tags.add(tag)
        
        # "其它地区" 包含未匹配的节点
        other_tags = [p['tag'] for p in proxies if p['tag'] not in matched_tags and not re.search(EXCLUDE_PATTERN, p['tag'])]
        if other_tags:
            region_map['🚞 其它地区'] = other_tags
            # 同步填充自动测速组（🛺 变体）
            region_map['🚞 其它地区🛺'] = other_tags
        
        # "全部节点" 包含所有非排除节点
        all_tags = [p['tag'] for p in proxies if not re.search(EXCLUDE_PATTERN, p['tag'])]
        region_map['🌐 全部节点'] = all_tags
        region_map['♻️ 自动选择'] = all_tags
        region_map['🔯 故障转移'] = all_tags
        region_map['🔮 负载均衡-轮询'] = all_tags
        region_map['🔮 负载均衡-散列'] = all_tags
        
        return region_map
    
    def _build_source_map(self, proxies: List[Dict], source_tags: List[str]) -> Dict[str, List[str]]:
        """构建订阅源分组"""
        source_map = {}
        
        for stag in source_tags:
            prefix = f'🎉 [{stag}]'
            matched = [p['tag'] for p in proxies if prefix in p['tag']]
            
            if matched:
                # urltest 组
                source_map[f'🎉 {stag}🛺'] = matched
                # selector 组
                source_map[f'🎉 {stag}'] = matched
        
        return source_map
    
    def _rebuild_outbound_refs(self, group: dict, region_map: dict, source_map: dict, proxies: List[Dict]):
        """重建分组的 outbounds 引用"""
        tag = group['tag']
        
        # 如果是订阅源分组或区域分组，直接设置
        if tag in source_map:
            group['outbounds'] = source_map[tag]
            return
        
        if tag in region_map:
            group['outbounds'] = region_map[tag] or ['🎯 全球直连']
            return
        
        # 其他分组：替换 placeholder
        old_refs = group.get('outbounds', [])
        new_refs = []
        replaced = False
        
        for ref in old_refs:
            if ref.startswith('🎉 ') and ref.endswith(('🛺', 'o')):  # placeholder
                if not replaced:
                    # 插入所有订阅源分组
                    for stag in sorted(source_map.keys()):
                        if stag not in new_refs:
                            new_refs.append(stag)
                    replaced = True
            else:
                if ref not in new_refs:
                    new_refs.append(ref)
        
        group['outbounds'] = new_refs or ['🎯 全球直连']
        
        # 清理 default 引用
        default = group.get('default')
        if default and default not in new_refs:
            group.pop('default', None)
    
    def _is_group_valid(self, group: dict, proxies: List[Dict]) -> bool:
        """检查分组是否有效（非空）"""
        if group['type'] not in ('selector', 'urltest'):
            return True
        
        outbounds = group.get('outbounds', [])
        return len(outbounds) > 0
    
    def save_runtime_config(self, output_file: str):
        """保存运行配置"""
        # 移除内部字段
        config = {k: v for k, v in self.config.items() if not k.startswith('_')}
        
        output_path = Path(output_file)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        
        with open(output_path, 'w', encoding='utf-8') as f:
            json.dump(config, f, ensure_ascii=False, indent=2)
        
        print(f"✓ 配置已保存: {output_file}")
    
    def run_update_loop(self, output_file: str):
        """守护进程模式"""
        def signal_handler(signum, frame):
            print("收到信号，退出...")
            self.running = False
        
        signal.signal(signal.SIGTERM, signal_handler)
        signal.signal(signal.SIGINT, signal_handler)
        
        while self.running:
            print(f"\n更新时间: {time.strftime('%Y-%m-%d %H:%M:%S')}")
            
            if self.update_proxies():
                self.save_runtime_config(output_file)
            else:
                print("更新失败，保留旧配置")
            
            if self.running:
                print(f"等待 {self.update_interval} 秒后下次更新...")
                time.sleep(self.update_interval)

def main():
    if len(sys.argv) < 2:
        print("用法: config_manager.py <模板配置> [输出文件] [once|daemon]")
        print()
        print("环境变量:")
        print("  SUBSCRIPTION_URL        基础订阅地址")
        print("  SUBSCRIPTION_TAG        基础订阅标签 (默认: default)")
        print("  SUBSCRIPTION_ENABLED    启用状态 (默认: true)")
        print("  SUBSCRIPTION_UA         User-Agent (默认: clash.meta)")
        print()
        print("  SUBSCRIPTION_URL_N      编号订阅地址 (N=1,2,3...)")
        print("  SUBSCRIPTION_TAG_N      编号订阅标签")
        print("  SUBSCRIPTION_ENABLED_N  编号启用状态")
        print("  SUBSCRIPTION_UA_N       编号 User-Agent")
        print()
        print("示例:")
        print("  export SUBSCRIPTION_URL_1='https://example.com/sub'")
        print("  export SUBSCRIPTION_TAG_1='airport'")
        print("  python3 config_manager.py template.json output.json once")
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
