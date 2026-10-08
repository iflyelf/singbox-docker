#!/bin/bash
#
# sing-box RuleSet 下载脚本
# - 从 GitHub 下载 sing-box 规则集（SRS 二进制格式）
# - 基于 config_with_sub.json 中的规则集列表
# - 支持代理下载
#
set -euo pipefail

# ============ 公共变量 ============
PROXY_URL="https://gh-proxy.com"
REPO_BASE="https://link.onlysing.com/get/singbox/ruleset"
SINGBOX_RULESET="/data/www/singbox/ruleset"
BASE_URL="${REPO_BASE}"

# ============ 规则映射 ============
# 格式："规则集名称"（自动添加 .srs 后缀）
RULES=(
  "AI"
  "Apple"
  "Bahamut"
  "BanAD"
  "BanEasyList"
  "BanEasyListChina"
  "BanEasyPrivacy"
  "BanProgramAD"
  "Bilibili"
  "BilibiliHMT"
  "ChinaCompanyIp"
  "ChinaDomain"
  "ChinaIp"
  "ChinaMedia"
  "Dns"
  "Download"
  "Epic"
  "IqiyiHMT"
  "LocalAreaNetwork"
  "Microsoft"
  "NetEaseMusic"
  "Netflix"
  "OneDrive"
  "OpenAi"
  "ProxyGFWlist"
  "ProxyMedia"
  "Sony"
  "Steam"
  "Telegram"
  "UnBan"
  "XiaoNuoDirect"
  "XiaoNuoProxy"
  "XiaoNuoReject"
  "YouTube"
)

# ============ 主逻辑 ============
echo "🚀 开始更新 sing-box RuleSet -> ${SINGBOX_RULESET}"
mkdir -p "${SINGBOX_RULESET}"
rm -rf "${SINGBOX_RULESET}"/*
sleep 0.5

fail=0
success=0
for rule in "${RULES[@]}"; do
  src="${rule}.srs"
  url="${BASE_URL}/${src}"
  if wget -q --no-check-certificate "${url}" -O "${SINGBOX_RULESET}/${src}"; then
    echo "✅ ${src}"
    success=$((success + 1))
  else
    echo "❌ 下载失败: ${url}"
    fail=$((fail + 1))
  fi
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 下载统计"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ 成功: ${success} 个"
echo "❌ 失败: ${fail} 个"
echo "📁 保存位置: ${SINGBOX_RULESET}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ ${fail} -eq 0 ]; then
  echo "🎉 所有规则集下载完成！"
else
  echo "⚠️ 部分规则集下载失败，请检查网络或 URL"
fi

exit "${fail}"
