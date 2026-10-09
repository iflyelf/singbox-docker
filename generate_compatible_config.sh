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
echo "  ✓ 已添加 download_detour 到所有远程 rule-set"
echo "  ✓ 已移除 routing_mark 字段（Windows/部分平台不支持）"
echo "  ✓ 已移除 route.default_mark 字段"
echo ""
echo "适用平台："
echo "  • Windows (解决 routing_mark 和 download_detour 问题)"
echo "  • macOS (跨平台兼容)"
echo "  • 其他需要显式 download_detour 的环境"
echo ""
echo "使用方法："
echo "  Linux:   sing-box run -c ${OUTPUT_CONFIG}"
echo "  Windows: sing-box.exe run -c ${OUTPUT_CONFIG}"
echo "  macOS:   sing-box run -c ${OUTPUT_CONFIG}"
