#!/bin/bash
# sing-box 订阅更新脚本
# 支持多格式订阅：Clash/Mihomo YAML、sing-box JSON、Base64/URI 分享链接

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_TEMPLATE="${SCRIPT_DIR}/conf/config_with_sub.json"
CONFIG_OUTPUT="${SCRIPT_DIR}/conf/config.json"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "sing-box 订阅更新脚本（多格式支持）"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# 加载 .env 文件（如果存在）
if [ -f "${SCRIPT_DIR}/.env" ]; then
    export $(grep -v '^#' "${SCRIPT_DIR}/.env" | xargs)
    echo "✓ 已加载 .env 文件"
fi

# 检查至少有一个订阅地址
if [ -z "${SUBSCRIPTION_URL_1}" ] && [ -z "${SUBSCRIPTION_URL}" ]; then
    echo "错误: 未设置订阅地址环境变量"
    echo ""
    echo "请在 .env 文件中配置："
    echo ""
    echo "  SUBSCRIPTION_URL_1='订阅地址1'"
    echo "  SUBSCRIPTION_TAG_1='66jc'"
    echo "  SUBSCRIPTION_ENABLED_1='true'"
    echo ""
    echo "  SUBSCRIPTION_URL_2='订阅地址2'"
    echo "  SUBSCRIPTION_TAG_2='yiyuan'"
    echo ""
    echo "支持格式: Clash YAML, sing-box JSON, Base64/URI"
    echo "支持协议: ss, vmess, vless, trojan, hysteria2, tuic, anytls"
    exit 1
fi

echo "配置模板: ${CONFIG_TEMPLATE}"
echo "输出配置: ${CONFIG_OUTPUT}"
echo ""

# 备份当前配置
if [ -f "${CONFIG_OUTPUT}" ]; then
    cp "${CONFIG_OUTPUT}" "${CONFIG_OUTPUT}.backup"
    echo "✓ 已备份当前配置"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "开始更新订阅..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if python3 "${SCRIPT_DIR}/scripts/config_manager.py" "${CONFIG_TEMPLATE}" "${CONFIG_OUTPUT}" once; then
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "✓ 订阅更新成功"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # 验证配置
    if command -v sing-box &> /dev/null; then
        echo ""
        if sing-box check -c "${CONFIG_OUTPUT}"; then
            echo "✓ 配置验证通过"
        else
            echo "⚠️ 配置验证失败"
        fi
    fi
    
    # 重启服务
    if docker ps --format '{{.Names}}' | grep -q "^singbox-client$"; then
        echo ""
        docker compose -f "${SCRIPT_DIR}/docker-compose-client.yml" restart
        echo "✓ 容器已重启"
    elif systemctl is-active --quiet singbox 2>/dev/null; then
        echo ""
        sudo systemctl restart singbox
        echo "✓ 服务已重启"
    fi
else
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "✗ 订阅更新失败"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # 恢复备份
    if [ -f "${CONFIG_OUTPUT}.backup" ]; then
        mv "${CONFIG_OUTPUT}.backup" "${CONFIG_OUTPUT}"
        echo "已恢复原配置"
    fi
    
    exit 1
fi
