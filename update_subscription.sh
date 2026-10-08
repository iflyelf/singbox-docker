#!/bin/bash
# sing-box 订阅更新脚本
# 使用 Docker 运行，无需本地安装 Python 和依赖
# 支持多订阅源

set -e

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_TEMPLATE="${SCRIPT_DIR}/conf/config_with_sub.json"
CONFIG_OUTPUT="${SCRIPT_DIR}/conf/config.json"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "sing-box 订阅更新脚本（多订阅源）"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# 检查至少有一个订阅地址
if [ -z "${CLASH_SUBSCRIPTION_URL_1}" ] && [ -z "${CLASH_SUBSCRIPTION_URL}" ]; then
    echo "错误: 未设置订阅地址环境变量"
    echo ""
    echo "使用方法（多订阅源）:"
    echo "  export CLASH_SUBSCRIPTION_URL_1='xiaonuo订阅地址'"
    echo "  export CLASH_SUBSCRIPTION_URL_2='其他机场订阅地址'"
    echo "  ./update_subscription.sh"
    echo ""
    echo "使用方法（单订阅源，兼容旧版）:"
    echo "  export CLASH_SUBSCRIPTION_URL='订阅地址'"
    echo "  ./update_subscription.sh"
    echo ""
    echo "说明:"
    echo "  - CLASH_SUBSCRIPTION_URL_1 对应 xiaonuo 标签前缀"
    echo "  - CLASH_SUBSCRIPTION_URL_2 对应 airport2 标签前缀"
    echo "  - 在 config_with_sub.json 中配置 enabled: true/false 启用/禁用"
    exit 1
fi

echo "配置模板: ${CONFIG_TEMPLATE}"
echo "输出配置: ${CONFIG_OUTPUT}"
echo ""

# 显示已配置的订阅源
[ -n "${CLASH_SUBSCRIPTION_URL_1}" ] && echo "✓ 订阅源 1 (xiaonuo): 已设置"
[ -n "${CLASH_SUBSCRIPTION_URL_2}" ] && echo "✓ 订阅源 2 (airport2): 已设置"
[ -n "${CLASH_SUBSCRIPTION_URL}" ] && echo "✓ 订阅源 (兼容模式): 已设置"

# 备份当前配置
if [ -f "${CONFIG_OUTPUT}" ]; then
    cp "${CONFIG_OUTPUT}" "${CONFIG_OUTPUT}.backup"
    echo "✓ 已备份当前配置"
fi

# 构建环境变量参数
ENV_ARGS=()
[ -n "${CLASH_SUBSCRIPTION_URL}" ] && ENV_ARGS+=(-e CLASH_SUBSCRIPTION_URL="${CLASH_SUBSCRIPTION_URL}")
[ -n "${CLASH_SUBSCRIPTION_URL_1}" ] && ENV_ARGS+=(-e CLASH_SUBSCRIPTION_URL_1="${CLASH_SUBSCRIPTION_URL_1}")
[ -n "${CLASH_SUBSCRIPTION_URL_2}" ] && ENV_ARGS+=(-e CLASH_SUBSCRIPTION_URL_2="${CLASH_SUBSCRIPTION_URL_2}")

# 使用 Docker 运行配置管理器
echo ""
echo "正在使用 Docker 更新订阅..."
docker run --rm \
  --user "$(id -u):$(id -g)" \
  "${ENV_ARGS[@]}" \
  -v "${SCRIPT_DIR}:/app" \
  -w /app \
  --entrypoint python3 \
  swr.cn-east-3.myhuaweicloud.com/iflyelf/singbox-client:latest \
  scripts/config_manager.py conf/config_with_sub.json conf/config.json once

if [ $? -eq 0 ]; then
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "✓ 订阅更新成功"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # 删除备份
    rm -f "${CONFIG_OUTPUT}.backup"
    
    echo ""
    echo "尝试重新加载配置..."
    
    # 检查是否有运行的容器
    if docker ps --format '{{.Names}}' | grep -q "singbox-client"; then
        echo "✓ 检测到 Docker 容器运行中"
        if [ -x "${SCRIPT_DIR}/reload_config.sh" ]; then
            "${SCRIPT_DIR}/reload_config.sh"
        else
            echo "⚠️ 重载脚本不存在或无执行权限"
            echo "手动重载: docker compose -f docker-compose-client.yml restart"
        fi
    elif systemctl is-active --quiet singbox 2>/dev/null; then
        echo "✓ 检测到 systemd 服务运行中"
        sudo systemctl reload singbox || sudo systemctl restart singbox
        echo "✓ 服务已重载"
    else
        echo ""
        echo "下一步:"
        echo "  1. 检查配置: sing-box check -c ${CONFIG_OUTPUT}"
        echo "  2. Docker: docker compose -f docker-compose-client.yml restart"
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
