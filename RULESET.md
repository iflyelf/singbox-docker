# sing-box 规则集下载脚本

## 脚本说明

`singbox-ruleset.sh` - 自动从 GitHub 下载 sing-box 规则集（SRS 二进制格式）

## 功能特性

- ✅ 自动下载 34 个规则集
- ✅ 使用 SRS 二进制格式（性能更好）
- ✅ 支持代理加速（gh-proxy.com）
- ✅ 基于配置文件中的规则列表
- ✅ 统计下载成功/失败数量
- ✅ 自动创建目标目录

## 使用方法

### 基本使用

```bash
# 直接运行
./singbox-ruleset.sh
```

### 自定义目录

编辑脚本中的变量：

```bash
# 修改保存目录
SINGBOX_RULESET="/your/custom/path"

# 修改代理地址（可选）
PROXY_URL="https://ghproxy.com"
```

### 无代理下载

```bash
# 编辑脚本，注释掉代理
# BASE_URL="${REPO_BASE}"  # 直接从 GitHub 下载
```

## 规则集列表

脚本会下载以下 34 个规则集：

### 拦截规则（6个）
- XiaoNuoReject
- BanAD
- BanProgramAD
- BanEasyList
- BanEasyListChina
- BanEasyPrivacy

### 直连规则（14个）
- XiaoNuoDirect
- LocalAreaNetwork
- ChinaIp
- ChinaDomain
- ChinaCompanyIp
- Download
- UnBan
- ChinaMedia
- Bilibili
- OneDrive
- Microsoft
- Apple
- Epic
- Sony

### 代理规则（14个）
- Steam
- NetEaseMusic
- Dns
- Telegram
- AI
- OpenAi
- YouTube
- Netflix
- Bahamut
- ProxyMedia
- BilibiliHMT
- IqiyiHMT
- ProxyGFWlist
- XiaoNuoProxy

## 输出示例

```
🚀 开始更新 sing-box RuleSet -> /data/www/singbox/ruleset
✅ AI.srs
✅ Apple.srs
✅ Bahamut.srs
...

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📊 下载统计
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ 成功: 34 个
❌ 失败: 0 个
📁 保存位置: /data/www/singbox/ruleset
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🎉 所有规则集下载完成！
```

## 配置使用

下载后的规则集可直接在 sing-box 配置中使用：

### 方式 1：使用本地文件

```json
{
  "route": {
    "rule_set": [
      {
        "tag": "Telegram",
        "type": "local",
        "format": "binary",
        "path": "/data/www/singbox/ruleset/Telegram.srs"
      }
    ]
  }
}
```

### 方式 2：使用远程 URL（推荐）

```json
{
  "route": {
    "rule_set": [
      {
        "tag": "Telegram",
        "type": "remote",
        "format": "binary",
        "url": "https://link.onlysing.com/get/singbox/ruleset/Telegram.srs"
      }
    ]
  }
}
```

## 定时更新

### 使用 crontab

```bash
# 编辑 crontab
crontab -e

# 添加：每天凌晨 3 点更新
0 3 * * * /path/to/singbox-ruleset.sh >> /var/log/singbox-ruleset.log 2>&1
```

### 使用 systemd timer

创建 `/etc/systemd/system/singbox-ruleset.service`：

```ini
[Unit]
Description=Update sing-box RuleSet

[Service]
Type=oneshot
ExecStart=/path/to/singbox-ruleset.sh
```

创建 `/etc/systemd/system/singbox-ruleset.timer`：

```ini
[Unit]
Description=Update sing-box RuleSet daily

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
```

启用定时器：

```bash
sudo systemctl enable --now singbox-ruleset.timer
```

## 故障排查

### 下载失败

1. 检查网络连接
2. 尝试不使用代理
3. 手动访问 URL 测试

### 权限问题

```bash
# 确保有写入权限
sudo mkdir -p /data/www/singbox/ruleset
sudo chown -R $USER:$USER /data/www/singbox
```

### 验证文件

```bash
# 检查文件大小
ls -lh /data/www/singbox/ruleset/

# 验证 SRS 文件
file /data/www/singbox/ruleset/*.srs
```

## 与 Clash 规则集对比

| 项目 | Clash | sing-box |
|------|-------|----------|
| 格式 | YAML | SRS 二进制 |
| 性能 | 一般 | 更好 |
| 大小 | 较大 | 较小 |
| 解析速度 | 较慢 | 更快 |

## 相关链接

- [规则集仓库](https://github.com/iflyelf/gwf)
- [sing-box 文档](https://sing-box.sagernet.org/zh/)
- [规则集转换工具](../gwf/scripts/convert_rules.py)

## 注意事项

⚠️ **下载前会清空目标目录**，请确保备份重要文件

⚠️ **需要网络访问** GitHub，或使用代理

⚠️ **SRS 格式** 是 sing-box 专用的二进制格式，Clash 无法使用
