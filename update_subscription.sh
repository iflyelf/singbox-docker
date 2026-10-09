#!/bin/bash
# sing-box 订阅更新脚本
# 使用 Docker 运行，无需本地安装 Python 和依赖
# 支持多订阅源，支持环境变量控制组名称和启用状态

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
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "使用方法 1: 完整配置（推荐）"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  export CLASH_SUBSCRIPTION_URL_1='订阅地址1'"
    echo "  export CLASH_SUBSCRIPTION_TAG_1='xiaonuo'        # 可选，默认为 airport1"
    echo "  export CLASH_SUBSCRIPTION_ENABLED_1='true'       # 可选，默认为 true"
    echo ""
    echo "  export CLASH_SUBSCRIPTION_URL_2='订阅地址2'"
    echo "  export CLASH_SUBSCRIPTION_TAG_2='airport2'       # 可选"
    echo "  export CLASH_SUBSCRIPTION_ENABLED_2='false'      # 可选，设为 false 禁用"
    echo ""
    echo "  ./update_subscription.sh"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "使用方法 2: 基础订阅（单源）"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  export CLASH_SUBSCRIPTION_URL='订阅地址'"
    echo "  export CLASH_SUBSCRIPTION_TAG='myairport'        # 可选"
    echo "  export CLASH_SUBSCRIPTION_ENABLED='true'         # 可选"
    echo "  ./update_subscription.sh"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "环境变量说明"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  CLASH_SUBSCRIPTION_URL_N    订阅地址（必填）"
    echo "  CLASH_SUBSCRIPTION_TAG_N    组名称/标签前缀（可选）"
    echo "  CLASH_SUBSCRIPTION_ENABLED_N 启用状态: true/false（可选）"
    echo ""
    echo "  支持 N = 1, 2, 3, ... 最多 99 个订阅源"
    echo "  启用状态可选值: true/1/yes/on 或 false/0/no/off"
    exit 1
fi

echo "配置模板: ${CONFIG_TEMPLATE}"
echo "输出配置: ${CONFIG_OUTPUT}"
echo ""

# 显示已配置的订阅源
if [ -n "${CLASH_SUBSCRIPTION_URL}" ]; then
    tag="${CLASH_SUBSCRIPTION_TAG:-default}"
    enabled="${CLASH_SUBSCRIPTION_ENABLED:-true}"
    echo "✓ 订阅源 (基础): tag=${tag}, enabled=${enabled}"
fi

for i in {1..10}; do
    url_var="CLASH_SUBSCRIPTION_URL_${i}"
    tag_var="CLASH_SUBSCRIPTION_TAG_${i}"
    enabled_var="CLASH_SUBSCRIPTION_ENABLED_${i}"
    
    if [ -n "${!url_var}" ]; then
        tag="${!tag_var:-airport${i}}"
        enabled="${!enabled_var:-true}"
        echo "✓ 订阅源 ${i}: tag=${tag}, enabled=${enabled}"
    fi
done

echo ""

# 备份当前配置
if [ -f "${CONFIG_OUTPUT}" ]; then
    cp "${CONFIG_OUTPUT}" "${CONFIG_OUTPUT}.backup"
    echo "✓ 已备份当前配置"
fi

# 构建环境变量参数（自动传递所有 CLASH_SUBSCRIPTION_* 变量）
ENV_ARGS=()

# 传递基础订阅变量
[ -n "${CLASH_SUBSCRIPTION_URL}" ] && ENV_ARGS+=(-e CLASH_SUBSCRIPTION_URL="${CLASH_SUBSCRIPTION_URL}")
[ -n "${CLASH_SUBSCRIPTION_TAG}" ] && ENV_ARGS+=(-e CLASH_SUBSCRIPTION_TAG="${CLASH_SUBSCRIPTION_TAG}")
[ -n "${CLASH_SUBSCRIPTION_ENABLED}" ] && ENV_ARGS+=(-e CLASH_SUBSCRIPTION_ENABLED="${CLASH_SUBSCRIPTION_ENABLED}")

# 传递编号订阅变量（1-20）
for i in {1..20}; do
    url_var="CLASH_SUBSCRIPTION_URL_${i}"
    tag_var="CLASH_SUBSCRIPTION_TAG_${i}"
    enabled_var="CLASH_SUBSCRIPTION_ENABLED_${i}"
    
    [ -n "${!url_var}" ] && ENV_ARGS+=(-e "${url_var}=${!url_var}")
    [ -n "${!tag_var}" ] && ENV_ARGS+=(-e "${tag_var}=${!tag_var}")
    [ -n "${!enabled_var}" ] && ENV_ARGS+=(-e "${enabled_var}=${!enabled_var}")
done

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
