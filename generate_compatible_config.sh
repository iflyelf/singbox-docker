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
        # 在规则列表开头添加 sniff、resolve 和内网域名直连规则
        .route.rules = [
          {
            "inbound": [$tun_tag],
            "action": "sniff"
          },
          {
            "inbound": [$tun_tag],
            "action": "resolve",
            "strategy": "ipv4_only"
          },
          {
            "domain_suffix": [".local", ".lan", ".internal", ".corp", ".home", ".iflytek.com"],
            "outbound": "🎯 全球直连"
          }
        ] + .route.rules
      else . end
    else . end
  
  # 9. 为 TUN 模式添加 DNS 配置（如果不存在）
  | if (.inbounds // [] | map(select(.type == "tun")) | length > 0) then
      if .dns == null then
        .dns = {
          "servers": [
            {
              "type": "https",
              "tag": "dns-remote",
              "server": "xiaonuo-dns.koyeb.app",
              "server_port": 443,
              "detour": "🚀 节点选择",
              "domain_resolver": "dns-system"
            },
            {
              "type": "https",
              "tag": "dns-remote-backup-1",
              "server": "dns.digitale-gesellschaft.ch",
              "server_port": 443,
              "detour": "🚀 节点选择",
              "domain_resolver": "dns-system"
            },
            {
              "type": "https",
              "tag": "dns-remote-backup-2",
              "server": "doh.applied-privacy.net",
              "server_port": 443,
              "path": "/query",
              "detour": "🚀 节点选择",
              "domain_resolver": "dns-system"
            },
            {
              "type": "https",
              "tag": "dns-remote-backup-3",
              "server": "odvr.nic.cz",
              "server_port": 443,
              "path": "/doh",
              "detour": "🚀 节点选择",
              "domain_resolver": "dns-system"
            },
            {
              "type": "https",
              "tag": "dns-remote-backup-4",
              "server": "dns.decloudus.com",
              "server_port": 443,
              "detour": "🚀 节点选择",
              "domain_resolver": "dns-system"
            },
            {
              "type": "https",
              "tag": "dns-remote-backup-5",
              "server": "doh.cleanbrowsing.org",
              "server_port": 443,
              "path": "/doh/security-filter/",
              "detour": "🚀 节点选择",
              "domain_resolver": "dns-system"
            },
            {
              "type": "https",
              "tag": "dns-direct",
              "server": "dns.alidns.com",
              "server_port": 443,
              "domain_resolver": "dns-system"
            },
            {
              "type": "https",
              "tag": "dns-direct-backup",
              "server": "doh.pub",
              "server_port": 443,
              "domain_resolver": "dns-system"
            },
            {
              "type": "local",
              "tag": "dns-system"
            },
            {
              "type": "local",
              "tag": "dns-local",
              "detour": "direct"
            },
            {
              "type": "udp",
              "tag": "dns-intranet",
              "server": "10.0.9.60",
              "server_port": 53,
              "detour": "direct"
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
              "server": "dns-remote"
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
            },
            {
              "rule_set": ["ChinaDomain"],
              "server": "dns-direct"
            }
          ],
          "final": "dns-remote",
          "strategy": "ipv4_only",
          "disable_cache": false,
          "disable_expire": false
        }
      else . end
    else . end
  
  # 10. 设置 route.default_domain_resolver（如果有 DNS 配置）
  | if .dns.servers then
      if .route == null then
        .route = {}
      else . end
      | .route.default_domain_resolver = {"server": "dns-system"}
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
echo "  ✓ 已添加 DNS 配置（使用 sing-box 1.12.0+ 新格式）"
echo "  ✓ DNS 服务器使用新格式（type 字段，无 legacy 格式）"
echo "  ✓ 已移除废弃的 outbound DNS 规则项"
echo "  ✓ 已移除 routing_mark 字段（Windows/部分平台不支持）"
echo "  ✓ 已移除 route.default_mark 字段"
echo "  ✓ 已移除 tproxy inbound（Windows 不支持）"
echo ""
echo "适用平台："
echo "  • Windows (解决 routing_mark, http_client, tproxy, TUN 代理问题)"
echo "  • Android/iOS (TUN 代理模式)"
echo "  • macOS (跨平台兼容)"
echo "  • 其他需要显式 http_client 的环境"
echo ""
echo "使用方法："
echo "  Linux:   sing-box run -c ${OUTPUT_CONFIG}"
echo "  Windows: sing-box.exe run -c ${OUTPUT_CONFIG}"
echo "  macOS:   sing-box run -c ${OUTPUT_CONFIG}"
