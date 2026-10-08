#!/bin/bash
#
# sing-box 配置重载脚本
# 在容器运行时重载配置，无需重启
#
set -e

CONTAINER_NAME="singbox-client"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "sing-box 配置重载"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# 检查容器是否运行
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "❌ 容器 ${CONTAINER_NAME} 未运行"
    echo ""
    echo "请先启动容器："
    echo "  docker-compose -f docker-compose-client.yml up -d"
    exit 1
fi

echo "✓ 容器正在运行"
echo ""

# 方式 1: 发送 SIGHUP 信号（推荐）
echo "方式 1: 发送 SIGHUP 信号重载配置..."
if docker exec ${CONTAINER_NAME} sh -c 'kill -HUP 1' 2>/dev/null; then
    echo "✓ 已发送 SIGHUP 信号"
else
    echo "⚠️ SIGHUP 信号发送失败，尝试重启容器..."
    docker-compose -f docker-compose-client.yml restart
    echo "✓ 容器已重启"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ 配置重载完成"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "查看日志："
echo "  docker logs -f ${CONTAINER_NAME}"
