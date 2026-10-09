#!/bin/bash
# Windows 平台专用配置生成脚本
# 自动处理 Windows 不支持的字段

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT_CONFIG="${1:-conf/config.json}"
OUTPUT_CONFIG="${2:-conf/win-config.json}"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Windows 平台配置转换工具"
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
# 1. 为所有远程 rule-set 添加 download_detour
# 2. 移除所有 routing_mark 字段
# 3. 移除 route.default_mark 字段
jq '
  # 1. 为远程 rule-set 添加 download_detour
  if .route.rule_set then
    .route.rule_set |= map(
      if .type == "remote" and (.download_detour == null) then
        . + {"download_detour": "🎯 全球直连"}
      else
        .
      end
    )
  else . end
  
  # 2. 移除 route 中的 routing_mark 相关字段
  | if .route then
      .route |= del(.default_mark)
    else . end
  
  # 3. 移除所有 outbound 中的 routing_mark
  | if .outbounds then
      .outbounds |= map(del(.routing_mark))
    else . end
  
  # 4. 移除所有 rule 中的 routing_mark
  | if .route.rules then
      .route.rules |= map(del(.routing_mark))
    else . end
' "${INPUT_CONFIG}" > "${OUTPUT_CONFIG}.tmp"

# 验证生成的配置
if sing-box check -c "${OUTPUT_CONFIG}.tmp" 2>/dev/null; then
    mv "${OUTPUT_CONFIG}.tmp" "${OUTPUT_CONFIG}"
    echo ""
    echo "✓ 配置转换成功: ${OUTPUT_CONFIG}"
    echo ""
    echo "Windows 平台适配："
    echo "  ✓ 已添加 download_detour 到所有远程 rule-set"
    echo "  ✓ 已移除 routing_mark 字段"
    echo "  ✓ 已移除 route.default_mark 字段"
    echo ""
    echo "使用方法："
    echo "  sing-box run -c ${OUTPUT_CONFIG}"
else
    rm -f "${OUTPUT_CONFIG}.tmp"
    echo ""
    echo "✗ 配置验证失败"
    echo ""
    echo "请检查输入配置是否正确"
    exit 1
fi
