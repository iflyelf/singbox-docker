#!/bin/bash
# 测试订阅环境变量功能

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "测试订阅环境变量功能"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# 测试 1: 单个订阅源
echo "【测试 1】单个订阅源"
export CLASH_SUBSCRIPTION_URL='https://example.com/sub'
export CLASH_SUBSCRIPTION_TAG='myairport'
export CLASH_SUBSCRIPTION_ENABLED='true'

python3 "${SCRIPT_DIR}/scripts/config_manager.py" \
    "${SCRIPT_DIR}/conf/config_with_sub.json" \
    "/tmp/test_config_1.json" \
    once 2>&1 | head -20

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# 测试 2: 多个订阅源
echo "【测试 2】多个订阅源"
unset CLASH_SUBSCRIPTION_URL
unset CLASH_SUBSCRIPTION_TAG
unset CLASH_SUBSCRIPTION_ENABLED

export CLASH_SUBSCRIPTION_URL_1='https://example1.com/sub'
export CLASH_SUBSCRIPTION_TAG_1='xiaonuo'
export CLASH_SUBSCRIPTION_ENABLED_1='true'

export CLASH_SUBSCRIPTION_URL_2='https://example2.com/sub'
export CLASH_SUBSCRIPTION_TAG_2='backup'
export CLASH_SUBSCRIPTION_ENABLED_2='false'

export CLASH_SUBSCRIPTION_URL_3='https://example3.com/sub'
export CLASH_SUBSCRIPTION_TAG_3='airport3'
export CLASH_SUBSCRIPTION_ENABLED_3='true'

python3 "${SCRIPT_DIR}/scripts/config_manager.py" \
    "${SCRIPT_DIR}/conf/config_with_sub.json" \
    "/tmp/test_config_2.json" \
    once 2>&1 | head -20

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# 测试 3: 环境变量覆盖配置文件
echo "【测试 3】环境变量覆盖配置文件中的 tag 和 enabled"
export CLASH_SUBSCRIPTION_URL_1='https://override.com/sub'
export CLASH_SUBSCRIPTION_TAG_1='override_tag'
export CLASH_SUBSCRIPTION_ENABLED_1='false'

python3 "${SCRIPT_DIR}/scripts/config_manager.py" \
    "${SCRIPT_DIR}/conf/config_with_sub.json" \
    "/tmp/test_config_3.json" \
    once 2>&1 | head -20

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "测试完成"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "说明:"
echo "  - 上面的错误是预期的（测试用 URL 无法访问）"
echo "  - 重点关注 '提示: 使用环境变量订阅配置' 信息"
echo "  - 以及实际使用的订阅源数量和配置"
