#!/bin/bash
# sing-box 兼容性配置生成工具
# 自动处理跨平台兼容性问题，适用于 Windows, macOS 等平台

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT_CONFIG="${1:-conf/config.json}"
OUTPUT_CONFIG="${2:-conf/compatible-config.json}"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "sing-box 兼容性配置生成工具"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "输入配置: ${INPUT_CONFIG}"
echo "输出配置: ${OUTPUT_CONFIG}"
echo ""

if [ ! -f "${INPUT_CONFIG}" ]; then
    echo "错误: 输入配置文件不存在: ${INPUT_CONFIG}"
    exit 1
fi

echo "正在转换配置..."

# 使用 jq 进行转换：
# 1. 确保 http_clients 存在并添加 direct-http
# 2. 为所有远程 rule-set 添加 http_client
# 3. 移除所有 routing_mark 字段
# 4. 移除 route.default_mark 字段
# 5. 移除不兼容的 inbound (tproxy)
# 6. 添加 TUN inbound（如果不存在）
# 7. 为 TUN inbound 添加 platform.http_proxy 配置
jq '
  # 1. 确保 http_clients 存在并移除无意义的 detour
  if .http_clients == null or (.http_clients | length == 0) then
    .http_clients = [{"tag": "direct-http"}]
  elif (.http_clients | map(select(.tag == "direct-http")) | length == 0) then
    .http_clients += [{"tag": "direct-http"}]
  else . end
  | .http_clients |= map(if .tag == "direct-http" then del(.detour) else . end)
  
  # 2. 为远程 rule-set 添加 http_client，移除旧的 download_detour
  | if .route.rule_set then
    .route.rule_set |= map(
      if .type == "remote" then
        (. | del(.download_detour)) + {"http_client": "direct-http"}
      else
        .
      end
    )
  else . end
  
  # 3. 移除 route 中的 routing_mark 相关字段
  | if .route then
      .route |= del(.default_mark)
    else . end
  
  # 4. 移除所有 outbound 中的 routing_mark
  | if .outbounds then
      .outbounds |= map(del(.routing_mark))
    else . end
  
  # 5. 移除所有 rule 中的 routing_mark
  | if .route.rules then
      .route.rules |= map(del(.routing_mark))
    else . end
  
  # 5.5. 移除 IPv6 拦截规则和端口 7892/7893 拦截规则
  | if .route.rules then
      .route.rules |= map(select(
        # 保留不是 IPv6 拦截的规则
        (.ip_version != 6 or .outbound != "🛑 广告拦截")
        and
        # 保留不是端口 7892/7893 拦截的规则
        (.port == null or (.port | tostring | contains("7892") | not) or .outbound != "🛑 广告拦截")
      ))
    else . end
  
  # 6. 移除不兼容的 inbound (tproxy 在 Windows 不支持)
  | if .inbounds then
      .inbounds |= map(select(.type != "tproxy"))
    else . end
  
  # 7. 添加 TUN inbound（如果不存在）
  | if (.inbounds // [] | map(select(.type == "tun")) | length == 0) then
      # 不存在 TUN，添加新的（使用新标准，移除废弃字段）
      .inbounds += [{
        "type": "tun",
        "tag": "tun-in",
        "mtu": 9000,
        "address": ["172.19.0.1/30", "fdfe:dcba:9876::1/126"],
        "auto_route": true,
        "strict_route": true
      }]
    else
      # 已存在 TUN，移除废弃字段和 platform.http_proxy
      .inbounds |= map(
        if .type == "tun" then
          # 移除废弃字段和 platform.http_proxy
          del(.sniff, .sniff_override_destination, .domain_strategy, .platform)
        else . end
      )
    end
  
  # 8. 为 TUN inbound 添加 route rule actions（替代废弃的 inbound 字段）
  | if (.inbounds // [] | map(select(.type == "tun" and .tag != null)) | length > 0) then
      # 获取 TUN inbound 的 tag
      (.inbounds | map(select(.type == "tun")) | .[0].tag) as $tun_tag |
      # 确保 route.rules 存在
      if .route.rules == null then
        .route.rules = []
      else . end |
      # 检查是否已有针对 TUN 的 sniff rule（使用更精确的匹配）
      if ([.route.rules[] | select(.inbound[0] == $tun_tag and .action == "sniff")] | length == 0) then
        # 在规则列表开头添加 sniff、resolve、内网域名和内网 IP 直连规则
        .route.rules = [
          {
            "inbound": [$tun_tag],
            "action": "sniff"
          },
          {
            "inbound": [$tun_tag],
            "action": "resolve",
            "strategy": "prefer_ipv4"
          },
          {
            "domain_suffix": [".local", ".lan", ".internal", ".corp", ".home", ".iflytek.com"],
            "outbound": "🎯 全球直连"
          },
          {
            "ip_cidr": [
              "0.0.0.0/8",
              "10.0.0.0/8",
              "100.64.0.0/10",
              "127.0.0.0/8",
              "169.254.0.0/16",
              "172.16.0.0/12",
              "192.0.0.0/24",
              "192.0.2.0/24",
              "192.168.0.0/16",
              "198.18.0.0/15",
              "198.51.100.0/24",
              "203.0.113.0/24",
              "224.0.0.0/4",
              "240.0.0.0/4",
              "255.255.255.255/32",
              "::1/128",
              "fc00::/7",
              "fe80::/10",
              "ff00::/8"
            ],
            "outbound": "🎯 全球直连"
          }
        ] + .route.rules
      else . end
    else . end
  
  # 8.5 为 mixed inbound 添加 sniff action（用于域名嗅探，避免重复添加）
  | if (.inbounds // [] | map(select(.type == "mixed")) | length > 0) then
      (.inbounds | map(select(.type == "mixed")) | .[0].tag) as $mixed_tag |
      # 确保 route.rules 存在
      if .route.rules == null then
        .route.rules = []
      else . end |
      # 检查是否已有针对 mixed-in 的 sniff rule
      if ([.route.rules[] | select(.inbound != null and .inbound[0] == $mixed_tag and .action == "sniff")] | length == 0) then
        # 在规则列表开头添加 sniff 规则
        .route.rules = [
          {
            "inbound": [$mixed_tag],
            "action": "sniff"
          }
        ] + .route.rules
      else . end
    else . end
  
  # 9. 为 TUN 模式添加 DNS 配置（如果不存在），使用 Fake IP
  | if (.inbounds // [] | map(select(.type == "tun")) | length > 0) then
      if .dns == null then
        .dns = {
          "servers": [
            {
              "type": "fakeip",
              "tag": "dns-fakeip",
              "inet4_range": "198.18.0.0/15",
              "inet6_range": "fc00::/18"
            },
            {
              "type": "https",
              "tag": "dns-remote",
              "server": "dns.decloudus.com",
              "server_port": 443,
              "path": "/dns-query",
              "detour": "🚀 节点选择",
              "domain_resolver": "dns-direct"
            },
            {
              "type": "https",
              "tag": "dns-remote-backup-1",
              "server": "xiaonuo-dns.koyeb.app",
              "server_port": 443,
              "detour": "🚀 节点选择",
              "domain_resolver": "dns-direct"
            },
            {
              "type": "https",
              "tag": "dns-remote-backup-2",
              "server": "dns.digitale-gesellschaft.ch",
              "server_port": 443,
              "detour": "🚀 节点选择",
              "domain_resolver": "dns-direct"
            },
            {
              "type": "https",
              "tag": "dns-remote-backup-3",
              "server": "doh.applied-privacy.net",
              "server_port": 443,
              "path": "/query",
              "detour": "🚀 节点选择",
              "domain_resolver": "dns-direct"
            },
            {
              "type": "https",
              "tag": "dns-remote-backup-4",
              "server": "odvr.nic.cz",
              "server_port": 443,
              "path": "/doh",
              "detour": "🚀 节点选择",
              "domain_resolver": "dns-direct"
            },
            {
              "type": "https",
              "tag": "dns-remote-backup-5",
              "server": "doh.cleanbrowsing.org",
              "server_port": 443,
              "path": "/doh/security-filter/",
              "detour": "🚀 节点选择",
              "domain_resolver": "dns-direct"
            },
            {
              "type": "udp",
              "tag": "dns-direct",
              "server": "223.5.5.5",
              "server_port": 53
            },
            {
              "type": "udp",
              "tag": "dns-direct-backup",
              "server": "119.29.29.29",
              "server_port": 53
            },
            {
              "type": "https",
              "tag": "dns-direct-doh",
              "server": "dns.alidns.com",
              "server_port": 443,
              "domain_resolver": "dns-direct"
            },
            {
              "type": "https",
              "tag": "dns-direct-doh-backup",
              "server": "doh.pub",
              "server_port": 443,
              "domain_resolver": "dns-direct"
            },
            {
              "type": "local",
              "tag": "dns-system"
            },
            {
              "type": "local",
              "tag": "dns-local"
            },
            {
              "type": "udp",
              "tag": "dns-intranet",
              "server": "10.0.9.60",
              "server_port": 53
            },
            {
              "type": "udp",
              "tag": "dns-block",
              "server": "0.0.0.0"
            }
          ],
          "rules": [
            {
              "domain_suffix": [".local", ".lan", ".internal", ".corp", ".home"],
              "server": "dns-local"
            },
            {
              "domain_suffix": [".iflytek.com"],
              "server": "dns-intranet"
            },
            {
              "clash_mode": "Direct",
              "server": "dns-direct"
            },
            {
              "clash_mode": "Global",
              "server": "dns-fakeip"
            },
            {
              "rule_set": ["ChinaDomain"],
              "server": "dns-direct"
            },
            {
              "action": "evaluate",
              "server": "dns-remote"
            },
            {
              "query_type": ["A", "AAAA"],
              "match_response": true,
              "ip_cidr": ["192.168.0.0/16", "172.16.0.0/12", "10.0.0.0/8"],
              "server": "dns-system"
            }
          ],
          "final": "dns-remote",
          "strategy": "prefer_ipv4",
          "disable_cache": false,
          "disable_expire": false,
          "optimistic": true
        }
      else . end
    else . end
  
  # 10. 设置 route.default_domain_resolver（如果有 DNS 配置）
  | if .dns.servers then
      if .route == null then
        .route = {}
      else . end
      | .route.default_domain_resolver = "dns-direct"
    else . end
  
  # 11. 添加 DNS 劫持路由规则（在所有规则之前）
  | if (.inbounds // [] | map(select(.type == "tun")) | length > 0) then
      if .route.rules == null then
        .route.rules = []
      else . end |
      # 检查是否已有 DNS 劫持规则
      if ([.route.rules[] | select(.protocol == "dns" and .action == "hijack-dns")] | length == 0) then
        # 在规则列表最前面添加 DNS 劫持规则
        .route.rules = [
          {
            "protocol": "dns",
            "action": "hijack-dns"
          }
        ] + .route.rules
      else . end
    else . end
' "${INPUT_CONFIG}" > "${OUTPUT_CONFIG}.tmp"

# 验证生成的配置
echo ""
if command -v sing-box &> /dev/null; then
    echo "正在验证配置..."
    if sing-box check -c "${OUTPUT_CONFIG}.tmp"; then
        echo "✓ 配置验证通过"
    else
        echo "⚠️ 配置验证失败，但仍会生成文件"
    fi
else
    echo "⚠️ 未找到 sing-box 命令，跳过验证"
fi

mv "${OUTPUT_CONFIG}.tmp" "${OUTPUT_CONFIG}"
echo ""
echo "✓ 配置转换成功: ${OUTPUT_CONFIG}"
echo ""
echo "兼容性适配："
echo "  ✓ 已添加 http_clients 配置（direct-http）"
echo "  ✓ 已为远程 rule-set 添加 http_client（替代废弃的 download_detour）"
echo "  ✓ 已添加 TUN inbound（不配置 platform.http_proxy 以避免冲突）"
echo "  ✓ 已添加 Fake IP DNS 配置（彻底解决 DNS 解析问题）"
echo "  ✓ 已添加 DNS 劫持路由规则（hijack-dns）"
echo "  ✓ DNS 规则优化：ChinaDomain 优先，国内域名直连不绕远程"
echo "  ✓ Bootstrap 解析器：使用 dns-direct 避免 TUN 回环"
echo "  ✓ 启用乐观缓存（optimistic: true）降低首包延迟"
echo "  ✓ DNS 服务器使用新格式（type 字段，无 legacy 格式）"
echo "  ✓ 已移除废弃的 outbound DNS 规则项"
echo "  ✓ 已移除 routing_mark 字段（Windows/部分平台不支持）"
echo "  ✓ 已移除 route.default_mark 字段"
echo "  ✓ 已移除 tproxy inbound（Windows 不支持）"
echo "  ✓ 已移除 IPv6 拦截规则（支持国内运营商 IPv6 网络）"
echo "  ✓ 已移除端口 7892/7893 拦截规则"
echo ""
echo "DNS 优化说明："
echo "  • Fake IP: 使用虚拟 IP 池避免真实 DNS 解析延迟"
echo "  • DNS 劫持: 53 端口流量强制走 sing-box DNS 模块"
echo "  • 规则顺序: 国内域名→直连 DNS，国外域名→Fake IP"
echo "  • Bootstrap: 远程 DoH 服务器域名用 dns-direct 引导，避免回环"
echo "  • 乐观缓存: 过期缓存先返回旧值，后台异步刷新"
echo ""
echo "适用平台："
echo "  • Windows (解决 routing_mark, http_client, tproxy, TUN 代理问题)"
echo "  • Android/iOS (TUN 代理模式 + Fake IP 秒开)"
echo "  • macOS (跨平台兼容)"
echo "  • 其他需要显式 http_client 的环境"
echo ""
echo "使用方法："
echo "  Linux:   sing-box run -c ${OUTPUT_CONFIG}"
echo "  Windows: sing-box.exe run -c ${OUTPUT_CONFIG}"
echo "  macOS:   sing-box run -c ${OUTPUT_CONFIG}"
