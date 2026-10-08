# sing-box 配置文件说明

## 配置文件

- `config_with_sub.json` - 配置模板（包含订阅配置）
- `config.json` - 运行时配置（由脚本生成）

## 配置结构说明

### 1. 订阅配置 (_subscription)

```json
{
  "_subscription": {
    "_comment": "订阅配置 - 类似 Clash 的 proxy-providers",
    "url": "env:CLASH_SUBSCRIPTION_URL",    // 订阅地址，支持环境变量
    "update_interval": 3600,                // 更新间隔（秒）
    "auto_update": true,                    // 是否自动更新
    "user_agent": "clash"                   // HTTP User-Agent
  }
}
```

**说明**:
- `url`: 支持 `env:变量名` 或直接写 URL
- 此字段仅在模板中使用，运行时配置不包含

### 2. 日志配置 (log)

```json
{
  "log": {
    "level": "info",      // 日志级别: trace, debug, info, warn, error
    "timestamp": true     // 是否显示时间戳
  }
}
```

### 3. 实验性功能 (experimental)

#### 缓存文件

```json
{
  "cache_file": {
    "enabled": true,           // 启用缓存
    "path": "cache.db",        // 缓存文件路径
    "store_fakeip": false      // 是否存储 FakeIP
  }
}
```

#### Clash API

```json
{
  "clash_api": {
    "external_controller": ":9090",  // API 端口
    "external_ui": "ui",             // Web 面板目录
    "secret": "@admin123",           // API 密钥
    "default_mode": "rule"           // 默认模式: rule, global, direct
  }
}
```

**访问**:
- API: `http://127.0.0.1:9090`
- 面板: `http://127.0.0.1:9090/ui`
- Secret: `@admin123`

### 4. DNS 配置 (dns)

```json
{
  "dns": {
    "servers": [],              // DNS 服务器列表（空=禁用）
    "rules": [],                // DNS 路由规则
    "strategy": "prefer_ipv4",  // 解析策略
    "disable_cache": true,      // 禁用缓存
    "disable_expire": true      // 禁用过期
  }
}
```

**说明**: DNS 已完全禁用，使用系统 DNS（smartdns）

### 5. 入站配置 (inbounds)

#### Mixed 代理（HTTP + SOCKS5）

```json
{
  "type": "mixed",        // 类型: 混合代理
  "tag": "mixed-in",      // 标签
  "listen": "::",         // 监听地址（IPv6 通配）
  "listen_port": 7890     // 监听端口
}
```

**用途**: HTTP 和 SOCKS5 代理（推荐使用）

#### SOCKS 代理

```json
{
  "type": "socks",        // 类型: SOCKS5
  "tag": "socks-in",      // 标签
  "listen": "::",         // 监听地址
  "listen_port": 7891     // 监听端口
}
```

#### TProxy 透明代理

```json
{
  "type": "tproxy",       // 类型: 透明代理
  "tag": "tproxy-in",     // 标签
  "listen": "::",         // 监听地址
  "listen_port": 7893     // 监听端口
}
```

**用途**: 旁路由、网关代理

### 6. 出站配置 (outbounds)

#### 代理组类型

**选择器 (selector)**
```json
{
  "type": "selector",     // 类型: 手动选择
  "tag": "🚀 节点选择",   // 标签
  "outbounds": [],        // 可选节点列表
  "default": "♻️ 自动选择"  // 默认节点
}
```

**自动选择 (urltest)**
```json
{
  "type": "urltest",           // 类型: 自动选择
  "tag": "♻️ 自动选择",        // 标签
  "outbounds": [],             // 节点列表
  "url": "https://www.gstatic.com/generate_204",  // 测试 URL
  "interval": "30s",           // 测试间隔
  "tolerance": 10              // 容差（ms）
}
```

#### 特殊出站

**直连 (direct)**
```json
{
  "type": "direct",      // 类型: 直接连接
  "tag": "🎯 全球直连"   // 标签
}
```

**拦截 (block)**
```json
{
  "type": "block",       // 类型: 拦截
  "tag": "🛑 广告拦截"   // 标签
}
```

### 7. 路由配置 (route)

#### 规则集 (rule_set)

```json
{
  "tag": "Telegram",                    // 标签
  "type": "remote",                     // 类型: 远程
  "format": "binary",                   // 格式: binary (SRS)
  "url": "https://raw.githubusercontent.com/iflyelf/gwf/main/singbox/rule-set/Telegram.srs"
}
```

**格式**:
- `binary`: SRS 二进制格式（推荐，性能更好）
- `source`: JSON 格式

#### 路由规则 (rules)

```json
{
  "rule_set": "Telegram",     // 匹配规则集
  "outbound": "🚀 节点选择"   // 使用的出站
}
```

**规则类型**:
- `rule_set`: 规则集匹配
- `domain`: 域名匹配
- `domain_suffix`: 域名后缀
- `ip_cidr`: IP CIDR
- `geoip`: GeoIP

## 端口列表

| 服务 | 端口 | 协议 | 用途 |
|------|------|------|------|
| Mixed | 7890 | HTTP + SOCKS5 | 混合代理（推荐） |
| SOCKS | 7891 | SOCKS5 | SOCKS5 代理 |
| TProxy | 7893 | 透明代理 | 网关/旁路由 |
| Clash API | 9090 | HTTP | API 和 Web 面板 |

## 代理组说明

### 功能分组

- `🚀 节点选择` - 手动选择节点
- `♻️ 自动选择` - 自动选择最快节点
- `🔯 故障转移` - 故障时自动切换
- `🔮 负载均衡-轮询` - 轮询负载均衡
- `🔮 负载均衡-散列` - 散列负载均衡
- `🌐 全部节点` - 所有可用节点
- `🎯 全球直连` - 直接连接
- `🛑 广告拦截` - 拦截广告

### 服务分组

- `📲 Telegram` - Telegram 专用
- `🤖 AI` - AI 服务（ChatGPT 等）
- `📹 YouTube` - YouTube 专用
- `🎥 Netflix` - Netflix 专用
- `📺 哔哩哔哩` - B站专用
- 等等...

### 地区分组

每个地区有两个组：
- `🇭🇰 香港🛺` - 自动选择（urltest）
- `🇭🇰 香港` - 手动选择（selector）

支持的地区：
- 🇹🇼 台湾
- 🇭🇰 香港
- 🇯🇵 日本
- 🇸🇬 新加坡
- 🇰🇷 韩国
- 🇷🇺 俄罗斯
- 🇨🇦 加拿大
- 🇺🇸 美国
- 🇬🇧 英国
- 🇫🇷 法国
- 🇩🇪 德国
- 🇧🇷 巴西
- 🇳🇱 荷兰
- 🚞 其它地区

## 规则集列表

### 拦截规则（6个）
- XiaoNuoReject - 自定义拦截
- BanAD - 广告拦截
- BanProgramAD - 程序广告
- BanEasyList - EasyList
- BanEasyListChina - EasyList 中国
- BanEasyPrivacy - EasyPrivacy

### 直连规则（14个）
- XiaoNuoDirect - 自定义直连
- LocalAreaNetwork - 局域网
- ChinaIp - 中国 IP
- ChinaDomain - 中国域名
- ChinaCompanyIp - 中国公司 IP
- Download - 下载服务
- UnBan - 解锁规则
- ChinaMedia - 中国媒体
- Bilibili - 哔哩哔哩
- OneDrive - OneDrive
- Microsoft - 微软
- Apple - 苹果
- Epic - Epic Games
- Sony - 索尼

### 代理规则（14个）
- XiaoNuoProxy - 自定义代理
- ProxyGFWlist - GFW 列表
- Telegram - Telegram
- AI - AI 服务
- OpenAi - OpenAI
- YouTube - YouTube
- Netflix - Netflix
- Bahamut - 巴哈姆特
- ProxyMedia - 代理媒体
- BilibiliHMT - B站港澳台
- IqiyiHMT - 爱奇艺港澳台
- Steam - Steam
- NetEaseMusic - 网易云音乐
- Dns - DNS

## 修改配置

1. **修改端口**
   编辑 `inbounds` 部分的 `listen_port`

2. **修改 API 密钥**
   编辑 `experimental.clash_api.secret`

3. **添加规则集**
   在 `route.rule_set` 添加新规则集
   在 `route.rules` 添加对应规则

4. **修改订阅地址**
   编辑 `_subscription.url`（仅模板文件）

## 验证配置

```bash
sing-box check -c conf/config.json
```

## 更多信息

- [sing-box 官方文档](https://sing-box.sagernet.org/zh/)
- [配置示例](https://sing-box.sagernet.org/zh/configuration/)

## sing-box API

sing-box 提供原生的 API 服务（不同于 Clash API）。

### 配置

```json
{
  "services": [
    {
      "type": "api",
      "listen": "127.0.0.1",
      "listen_port": 9191,
      "secret": "@admin123",
      "access_control_allow_origin": ["*"],
      "access_control_allow_private_network": true,
      "dashboard": {
        "enabled": true,
        "path": "dashboard",
        "update_interval": "1d"
      }
    }
  ]
}
```

### 访问信息

- **API 地址**: `http://127.0.0.1:9191`
- **Dashboard**: `http://127.0.0.1:9191/dashboard/`
- **Secret**: `@admin123`

### API 端点

- `GET /` - API 信息
- `GET /traffic` - 实时流量统计
- `GET /connections` - 连接列表
- `DELETE /connections/:id` - 关闭连接
- `GET /logs` - 日志流
- `GET /dashboard/` - Web 仪表板

### Dashboard



### 与 Clash API 的区别

| 功能 | Clash API (9090) | sing-box API (9191) |
|------|------------------|---------------------|
| 协议 | Clash 兼容 | sing-box 原生 |
| 面板 | 第三方面板 | 官方仪表板 |
| 功能 | 节点管理、延迟测试 | 流量统计、连接管理、日志 |
| 兼容性 | Clash 客户端 | sing-box 专用 |

建议：
- 使用 **Clash API (9090)** 进行节点切换和管理
- 使用 **sing-box API (9191)** 查看流量统计和连接信息

