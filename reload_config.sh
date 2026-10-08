#!/bin/bash
#
# sing-box 配置重载脚本
# 在容器运行时重载配置，无需重启
#
set -euo pipefail

CONTAINER_NAME="singbox-client"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "sing-box 配置重载"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# 检查容器是否运行
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "❌ 容器 ${CONTAINER_NAME} 未运行"
    echo ""
    echo "请先启动容器："
    echo "  docker compose -f ${SCRIPT_DIR}/docker-compose-client.yml up -d"
    exit 1
fi

echo "✓ 容器正在运行"
echo ""

# 重启容器以确保完整加载新配置。
echo "重启客户端容器以加载新配置..."
docker compose \
    --project-directory "${SCRIPT_DIR}" \
    -f "${SCRIPT_DIR}/docker-compose-client.yml" \
    restart singbox
echo "✓ 容器已重启"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ 配置重载完成"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "查看日志："
echo "  docker logs -f ${CONTAINER_NAME}"
