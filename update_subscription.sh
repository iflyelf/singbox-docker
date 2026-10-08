#!/bin/bash
# sing-box 订阅更新脚本
# 使用 Docker 运行，无需本地安装 Python 和依赖

set -e

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_TEMPLATE="${SCRIPT_DIR}/conf/config_with_sub.json"
CONFIG_OUTPUT="${SCRIPT_DIR}/conf/config.json"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "sing-box 订阅更新脚本"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# 检查订阅地址
if [ -z "${CLASH_SUBSCRIPTION_URL}" ]; then
    echo "错误: 未设置 CLASH_SUBSCRIPTION_URL 环境变量"
    echo ""
    echo "使用方法:"
    echo "  export CLASH_SUBSCRIPTION_URL='你的订阅地址'"
    echo "  ./update_subscription.sh"
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

# 使用 Docker 运行配置管理器
echo ""
echo "正在使用 Docker 更新订阅..."
docker run --rm \
  -e CLASH_SUBSCRIPTION_URL="${CLASH_SUBSCRIPTION_URL}" \
  -v "${SCRIPT_DIR}:/app" \
  -w /app \
  swr.cn-east-3.myhuaweicloud.com/iflyelf/sing-box:latest \
  python3 scripts/config_manager.py conf/config_with_sub.json conf/config.json once

if [ $? -eq 0 ]; then
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "✓ 订阅更新成功"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # 删除备份
    rm -f "${CONFIG_OUTPUT}.backup"
    
    echo ""
    echo "尝试自动重载配置..."
    
    # 检查是否有运行的容器
    if docker ps --format '{{.Names}}' | grep -q "singbox-client"; then
        echo "✓ 检测到 Docker 容器运行中"
        if [ -x "${SCRIPT_DIR}/reload_config.sh" ]; then
            "${SCRIPT_DIR}/reload_config.sh"
        else
            echo "⚠️ 重载脚本不存在或无执行权限"
            echo "手动重载: docker-compose -f docker-compose-client.yml restart"
        fi
    elif systemctl is-active --quiet singbox 2>/dev/null; then
        echo "✓ 检测到 systemd 服务运行中"
        sudo systemctl reload singbox || sudo systemctl restart singbox
        echo "✓ 服务已重载"
    else
        echo ""
        echo "下一步:"
        echo "  1. 检查配置: sing-box check -c ${CONFIG_OUTPUT}"
        echo "  2. Docker: docker-compose -f docker-compose-client.yml restart"
        echo "  3. systemd: sudo systemctl restart singbox"
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
