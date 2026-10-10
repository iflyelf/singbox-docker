# singbox-docker

sing-box 客户端与服务端 Docker 镜像与配置。

- **客户端镜像** (`singbox-client`): 只运行 sing-box 和 nginx，用于代理客户端场景
- **服务端镜像** (`sing-box`): 包含 supervisord、VMess/Trojan 入站配置，用于代理服务器场景

## 目录

- [客户端 (Client)](#客户端-client)
  - [功能](#功能)
  - [镜像](#镜像)
  - [快速开始](#快速开始)
  - [配置说明](#配置说明)
  - [故障排查](#故障排查)
- [服务端 (Server)](#服务端-server)
  - [功能](#服务端功能)
  - [快速开始](#服务端快速开始)
  - [配置说明](#服务端配置说明)
- [安全建议](#安全建议)
- [参考](#参考)

---

# 客户端 (Client)

## 功能

- 使用最新稳定版 sing-box，构建时通过 GitHub API 获取版本
- 使用 `iflyelf/nginx:latest` 提供 nginx 运行产物
- 内置 zashboard，由 nginx 在 `9898` 端口提供
- Clash API 监听 `0.0.0.0:9090`
- sing-box 原生 API 监听 `0.0.0.0:9191`
- Mixed、SOCKS5、TProxy 分别监听 `7890`、`7891`、`7893`
- DNS 不由 sing-box 处理，直接使用系统 DNS（宿主机 smartdns）
- 使用远程 SRS 规则集
- **支持多个订阅源，每个订阅可指定标签前缀**
- 协议嗅探启用，TProxy 场景域名规则正常工作

## 镜像

国内推荐使用华为云 SWR：

```text
swr.cn-east-3.myhuaweicloud.com/iflyelf/singbox-client:latest
```

DockerHub：

```text
iflyelf/singbox-client:latest
```

客户端镜像由 GitHub Actions 自动构建和发布，支持 `linux/amd64` 和 `linux/arm64` 双架构。

## 快速开始

### 0. 克隆项目

**国内推荐使用加速镜像**：

```bash
git clone https://gh-proxy.xiaonuo.live/github.com/iflyelf/singbox-docker
cd singbox-docker
```

**或直接从 GitHub 克隆**：

```bash
git clone https://github.com/iflyelf/singbox-docker.git
cd singbox-docker
```

### 1. 启动客户端

```bash
docker compose -f docker-compose-client.yml pull
docker compose -f docker-compose-client.yml up -d
docker logs -f singbox-client
```

客户端编排使用 `host` 网络、TUN 设备和所需内核挂载。原服务端 `docker-compose.yml` 不受影响。

### 2. 跨平台兼容配置

部分平台（如 Windows、macOS）由于系统限制，不支持某些 Linux 特性（如 `routing_mark`），且远程 rule-set 需要显式指定下载出站。

**生成兼容性配置**：

```bash
# 1. 先按正常流程更新订阅生成 config.json
./update_subscription.sh

# 2. 转换为跨平台兼容配置
./generate_compatible_config.sh conf/config.json conf/compatible-config.json
```

**自动处理**：
- ✅ 添加 `http_clients` 配置（direct-http）
- ✅ 为所有远程 rule-set 添加 `http_client`（替代废弃的 `download_detour`）
- ✅ 添加 TUN inbound 并配置 `platform.http_proxy`（Windows/Android/iOS 必需）
- ✅ 移除 TUN 废弃字段（sniff, sniff_override_destination）
- ✅ 添加 route rule actions（sniff, resolve）替代 inbound 字段
- ✅ 移除 `routing_mark` 字段（Windows/部分平台不支持）
- ✅ 移除 `route.default_mark` 字段
- ✅ 移除 `tproxy` inbound（Windows 不支持）

**适用场景**：
- Windows 平台：解决 routing_mark, http_client, tproxy, TUN 代理等兼容性问题
- Android/iOS 平台：TUN 代理模式（无特权环境）
- macOS 平台：跨平台兼容性
- 其他需要显式 http_client 的环境

**移除的不兼容特性**：
- `tproxy` inbound：Windows 不支持透明代理
- `routing_mark`：Linux 特有的路由标记功能
- `route.default_mark`：依赖 routing_mark 的配置
- TUN `sniff` 字段：已在 sing-box 1.11.0 废弃，1.13.0 移除

**新特性（sing-box 1.14.0+）**：
- ✅ 使用 `http_client` 替代已废弃的 `download_detour`
- ✅ 符合 sing-box 1.16.0+ 要求（download_detour 将被移除）
- ✅ TUN inbound 自动配置 `platform.http_proxy`（代理模式，不捕获流量）
- ✅ 使用 route rule actions 替代废弃的 inbound sniff 字段

**启动方式**：

```bash
# Linux
sing-box run -c conf/compatible-config.json

# Windows (管理员权限)
sing-box.exe run -c conf\compatible-config.json

# macOS
sing-box run -c conf/compatible-config.json
```

**注意事项**：
- Windows/macOS 需要管理员权限运行（TUN 设备）
- 每次更新订阅后需要重新生成兼容配置
- `compatible-config.json` 不会提交到 Git（已加入 .gitignore）

### 3. 更新订阅

支持多种订阅格式自动识别：
- ✅ **Clash/Mihomo YAML** - 标准 Clash 配置格式
- ✅ **sing-box JSON** - 原生 sing-box 配置
- ✅ **Base64/URI** - vmess://, vless://, trojan://, ss://, hysteria2://, tuic://, anytls:// 等分享链接

支持协议：shadowsocks, vmess, vless (含 Reality), trojan, hysteria2, tuic, anytls (shadowtls v3)

#### 方式 1: 通过 .env 文件（推荐）

创建 `.env` 文件（不要提交到 Git）：

```bash
# 复制模板文件
cp .env.example .env

# 编辑填入真实订阅地址
nano .env
```

**.env 文件示例**：

```bash
# 订阅源 1
SUBSCRIPTION_URL_1='https://example1.com/subscription'
SUBSCRIPTION_TAG_1='66jc'
SUBSCRIPTION_ENABLED_1='true'

# 订阅源 2
SUBSCRIPTION_URL_2='https://example2.com/subscription'
SUBSCRIPTION_TAG_2='yiyuan'
SUBSCRIPTION_ENABLED_2='true'

# 自动更新配置
# 是否启用自动更新：true 或 false
SUBSCRIPTION_AUTO_UPDATE='true'
# 更新间隔（秒），3600 = 1 小时
SUBSCRIPTION_UPDATE_INTERVAL='3600'
```

**⚠️ 注意事项**：
- ❌ **不要使用行内注释**：`VAR='value' # comment` 会导致 export 解析错误
- ✅ **使用独立行注释**：注释必须单独成行
- ✅ **仓库提供 `.env.example` 模板**，复制后填入真实订阅地址
- ✅ **`.env` 文件已加入 `.gitignore`**，不会被提交到仓库

更新订阅：

```bash
./update_subscription.sh
```

**环境变量说明**：

| 环境变量 | 说明 | 必填 | 默认值 |
|---------|------|------|--------|
| `SUBSCRIPTION_URL_N` | 订阅地址 | ✅ | 无 |
| `SUBSCRIPTION_TAG_N` | 组名称/标签前缀 | ❌ | `airportN` |
| `SUBSCRIPTION_ENABLED_N` | 启用状态 (true/false) | ❌ | `true` |
| `SUBSCRIPTION_UA_N` | User-Agent | ❌ | `clash.meta` |
| `SUBSCRIPTION_AUTO_UPDATE` | 自动更新开关 | ❌ | `true` |
| `SUBSCRIPTION_UPDATE_INTERVAL` | 更新间隔（秒） | ❌ | `3600` |

- `N` 为订阅编号：1, 2, 3, ... 最多 99
- 不带编号的 `SUBSCRIPTION_URL` 也支持
- `enabled` 可选值：`true`/`1`/`yes`/`on` 或 `false`/`0`/`no`/`off`
- 自动更新功能：容器内定时拉取订阅并热重载配置（不重启容器）

**高级配置：覆盖监听端口、Clash API、API 服务与 routing_mark**

除订阅相关变量外，还可以通过环境变量覆盖模板（`config_with_sub.json`）中的入站、Clash API、API 服务及 routing_mark。这些变量均为**可选**，不设置时沿用模板默认值。

| 环境变量 | 说明 | 默认值（模板） |
|---------|------|----------------|
| `MIXED_LISTEN` | mixed 入站（HTTP + SOCKS 混合代理）监听地址 | `::` |
| `MIXED_PORT` | mixed 入站端口 | `7890` |
| `SOCKS_LISTEN` | socks 入站监听地址 | `::` |
| `SOCKS_PORT` | socks 入站端口 | `7891` |
| `TPROXY_LISTEN` | tproxy 入站（透明代理）监听地址 | `::` |
| `TPROXY_PORT` | tproxy 入站端口 | `7893` |
| `CLASH_API_EXTERNAL_CONTROLLER` | Clash API 外部控制器监听地址（`host:port`） | `0.0.0.0:9090` |
| `CLASH_API_SECRET` | Clash API 访问密码 | `@admin123` |
| `API_SERVICE_LISTEN` | sing-box API 服务监听地址 | `0.0.0.0` |
| `API_SERVICE_PORT` | sing-box API 服务端口 | `9191` |
| `API_SERVICE_SECRET` | sing-box API 服务访问密码 | `@admin123` |
| `ROUTING_MARK` | 覆盖所有已含 `routing_mark` 字段的出站（策略路由打标） | `100` |
| `ZASHBOARD_PORT` | zashboard（nginx）监听端口 | `9898` |

- 除 `ZASHBOARD_PORT` 外，上述覆盖仅在**通过订阅模板生成配置**的流程中生效（即设置了 `SUBSCRIPTION_URL*` 时）。若容器回退到静态挂载的 `conf/config.json`，不会应用这些变量。
- `ZASHBOARD_PORT` 作用于 nginx vhost 配置，在容器启动时改写监听端口，不依赖订阅流程，始终生效。
- 端口与 `ROUTING_MARK` 必须为整数，值无效时会打印警告并忽略该项。
- `secret` 在日志中以 `******` 脱敏显示。
- 入站覆盖按 `type` 匹配模板中的入站（mixed / socks / tproxy），而非按 tag。

`.env` 配置示例：

```bash
# 自定义入站端口
MIXED_PORT='17890'
SOCKS_PORT='17891'
TPROXY_PORT='17893'

# 自定义 Clash API
CLASH_API_EXTERNAL_CONTROLLER='0.0.0.0:19090'
CLASH_API_SECRET='your-strong-secret'

# 自定义 sing-box API 服务
API_SERVICE_LISTEN='0.0.0.0'
API_SERVICE_PORT='19191'
API_SERVICE_SECRET='your-strong-secret'

# 自定义 routing_mark
ROUTING_MARK='200'

# 自定义 zashboard（nginx）监听端口
ZASHBOARD_PORT='18898'
```

**组名称（Tag）作用**：

每个订阅源会生成独立的分组，便于管理和切换：

```
订阅源 tag: 66jc
生成分组: 🎉 66jc🛺 (自动选择), 🎉 66jc (手动选择)
节点标签: 🎉 [66jc] 香港 HKT01
```

区域分组自动填充：🇹🇼 台湾、🇭🇰 香港、🇯🇵 日本、🇸🇬 新加坡等

#### 方式 2: Docker Compose 自动生成配置

容器启动时自动检测环境变量，拉取订阅并生成运行配置。**支持订阅自动更新和热重载**（无需重启容器）。

`.env` 文件内容与[方式 1](#方式-1-通过-env-文件推荐)相同，参见上文的环境变量说明与示例。容器会通过 `env_file` 读取这些变量。

**docker-compose-client.yml**：

```yaml
services:
  singbox:
    image: swr.cn-east-3.myhuaweicloud.com/iflyelf/singbox-client:latest
    env_file:
      - path: .env
        required: false
    volumes:
      - ./conf/config.json:/etc/sing-box/config.json:ro,cached
      - ./conf/config_with_sub.json:/etc/sing-box/config_with_sub.json:ro,cached
      - ./runtime:/etc/sing-box/runtime:rw,cached  # 持久化运行时配置
```

启动容器：

```bash
docker compose -f docker-compose-client.yml up -d
```

查看订阅是否生效：

```bash
docker logs singbox-client | grep -E "订阅源|使用配置"
```

**工作原理**：

- ✅ 检测到 `SUBSCRIPTION_URL*` 环境变量：拉取订阅，生成 `/etc/sing-box/runtime/config.json` 并启动
- ✅ 配置持久化到宿主机 `./runtime/config.json`（容器重启后保留）
- ❌ 未设置订阅变量：直接使用挂载的 `conf/config.json`
- ⚠️ 订阅拉取失败：回退到挂载的 `conf/config.json` 或上次成功生成的配置

**配置文件说明**：

| 路径 | 用途 | 持久化 | 说明 |
|-----|------|-------|------|
| `./conf/config.json` | 静态配置/回退配置 | ✅ 宿主机 | 只读挂载，手动更新用 |
| `./conf/config_with_sub.json` | 订阅配置模板 | ✅ 宿主机 | 只读挂载，定义配置结构 |
| `./runtime/config.json` | 容器运行时配置 | ✅ 宿主机 | 读写挂载，容器自动生成 |

**自动更新机制**：

1. **启动时初始化**：容器启动时立即拉取订阅生成配置
2. **定时自动更新**：后台任务按设定间隔（默认1小时）自动拉取订阅
3. **热重载配置**：更新成功后向 sing-box 发送 HUP 信号，实现无缝重载（不中断连接）
4. **失败保护**：更新失败时保持当前配置继续运行
5. **配置持久化**：自动生成的配置保存到 `./runtime/config.json`，容器重启后保留

查看自动更新日志：

```bash
docker logs -f singbox-client | grep "自动更新\|订阅源\|重载"
```

查看运行时配置：

```bash
# 查看容器生成的配置文件
cat runtime/config.json

# 或生成跨平台兼容配置用于本地测试
./generate_compatible_config.sh runtime/config.json conf/compatible-config.json
```

禁用自动更新：

```bash
# 在 .env 中设置
SUBSCRIPTION_AUTO_UPDATE='false'
```

修改订阅源后重启容器：

```bash
docker compose -f docker-compose-client.yml restart
```

#### 方式 3: 手动 export（单次使用）

```bash
export SUBSCRIPTION_URL_1='https://example.com/sub'
export SUBSCRIPTION_TAG_1='myairport'
./update_subscription.sh
```

#### 节点分组规则

**订阅源分组**（自动生成）：
- 每个订阅源生成两个分组：
  - `🎉 {tag}🛺` - urltest 自动选择最快节点
  - `🎉 {tag}` - selector 手动选择节点
- 节点标签格式：`🎉 [{tag}] 节点名`

**区域分组**（智能匹配）：
- 🇹🇼 台湾、🇭🇰 香港、🇯🇵 日本、🇸🇬 新加坡、🇰🇷 韩国
- 🇷🇺 俄罗斯、🇨🇦 加拿大、🇺🇸 美国、🇬🇧 英国、🇫🇷 法国等
- 🚞 其它地区（未匹配到的节点）

**全局分组**：
- 🌐 全部节点 - 所有订阅源的全部节点
- ♻️ 自动选择 - urltest 自动选择最快
- 🔯 故障转移 - 主节点失败时切换
- 🔮 负载均衡 - 轮询/散列策略

**工作流程**：

1. 读取环境变量中的订阅配置
2. 拉取订阅，自动识别格式（Clash YAML / sing-box JSON / Base64 URI）
3. 转换为 sing-box outbound 格式
4. 根据 tag 创建订阅源分组
5. 根据节点名匹配区域分组
6. 生成 `conf/config.json`（或容器内 `/etc/sing-box/runtime/config.json`）

### 4. 重新加载配置

```bash
./reload_config.sh
```

脚本会重启 `singbox-client` 容器。配置文件已挂载到容器内，重启后会完整加载新配置。

## 管理界面与 API

| 服务 | 地址 | 用途 |
|------|------|------|
| zashboard | `http://<服务器IP>:9898` | 通过 Clash API 管理节点（端口可用 `ZASHBOARD_PORT` 自定义） |
| Clash API | `http://<服务器IP>:9090` | 节点切换、延迟测试、连接管理（可用 `CLASH_API_*` 自定义） |
| sing-box API | `http://<服务器IP>:9191` | 原生 gRPC/gRPC-Web API（可用 `API_SERVICE_*` 自定义） |

默认 API 密钥：

```text
@admin123
```

zashboard 首次打开后填写：

- API 地址：`http://<服务器IP>:9090`
- Secret：`@admin123`

客户端镜像构建时已经打包 zashboard，不会在容器启动时从 GitHub 下载。

## 代理端口

| 端口 | 类型 | 自定义环境变量 |
|------|------|----------------|
| `7890` | Mixed（HTTP + SOCKS5） | `MIXED_PORT` / `MIXED_LISTEN` |
| `7891` | SOCKS5 | `SOCKS_PORT` / `SOCKS_LISTEN` |
| `7893` | TProxy | `TPROXY_PORT` / `TPROXY_LISTEN` |
| `9090` | Clash API | `CLASH_API_EXTERNAL_CONTROLLER` |
| `9191` | sing-box API | `API_SERVICE_PORT` / `API_SERVICE_LISTEN` |
| `9898` | zashboard | `ZASHBOARD_PORT` |

## 性能优化

### DNS 配置

**已彻底移除 sing-box DNS 配置！**

- ✅ 规则集下载使用系统 DNS（宿主机 smartdns）
- ✅ 用户流量直接走系统 DNS
- ✅ 零 DNS 查询延迟

### 协议嗅探

- ✅ 启用 HTTP/TLS/QUIC 协议嗅探
- ✅ TProxy 场景自动提取真实域名用于路由匹配
- ✅ 域名规则正常工作

### 路由优化

- ✅ 本地回环直连前置
- ✅ IPv6 流量明确拒绝（系统不支持时避免超时）
- ✅ 规则顺序优化：嗅探 → 本地 → IPv6拒绝 → 广告 → 直连 → 代理

### 规则集

- ✅ **ChinaIp**: 5958 条规则
- ✅ **ChinaDomain**: 完整域名规则
- ✅ 百度等国内网站正确命中直连
- ✅ 所有规则集已编译为 SRS 二进制格式

运行配置使用以下远程 SRS 地址：

```text
https://link.onlysing.com/get/singbox/ruleset/<规则集名称>.srs
```

如需将规则集下载到本地：

```bash
./singbox-ruleset.sh
```

默认目录：

```text
/data/www/singbox/ruleset
```

## 配置验证

本机已安装 sing-box 时：

```bash
sing-box check -c conf/config.json
```

未安装时可使用客户端镜像：

```bash
docker run --rm \
  -v "$PWD/conf/config.json:/etc/sing-box/config.json:ro" \
  --entrypoint /usr/bin/sing-box \
  swr.cn-east-3.myhuaweicloud.com/iflyelf/singbox-client:latest \
  check -c /etc/sing-box/config.json
```

## 常用命令

```bash
# 启动
docker compose -f docker-compose-client.yml up -d

# 查看日志
docker logs -f singbox-client

# 订阅更新（需先创建 .env 文件）
./update_subscription.sh

# 重新加载配置
./reload_config.sh

# 停止
docker compose -f docker-compose-client.yml down
```

## 故障排查

### 订阅更新失败

```bash
# 检查环境变量
env | grep SUBSCRIPTION_URL

# 查看 .env 文件
cat .env
curl -v "你的订阅地址"
```

### 规则集下载超时

检查系统 DNS 是否正常：

```bash
# 测试域名解析
nslookup link.onlysing.com

# 检查 smartdns 状态
systemctl status smartdns
```

### 节点未分组

检查 `config_with_sub.json` 中的 `tag_prefix` 是否与代理组名称匹配。

### 查看日志

```bash
docker logs -f singbox-client
```

---

# 服务端 (Server)

## 服务端功能

- 使用最新稳定版 sing-box
- 使用 supervisord 管理多个服务进程
- 支持 VMess、Trojan、Shadowsocks 等入站协议
- 内置多种出站配置（Direct、Block、DNS）
- 支持完整的路由规则和规则集
- TLS 证书自动管理（可选）
- 服务端监控和日志管理

## 服务端快速开始

### 0. 克隆项目

**国内推荐使用加速镜像**：

```bash
git clone https://gh-proxy.xiaonuo.live/github.com/iflyelf/singbox-docker
cd singbox-docker
```

**或直接从 GitHub 克隆**：

```bash
git clone https://github.com/iflyelf/singbox-docker.git
cd singbox-docker
```

### 1. 部署服务端

```bash
cd /path/to/singbox-docker

# 编辑配置文件
vim config/server-config.json

# 使用 docker-compose.yml 启动服务端
docker-compose up -d singbox

# 查看日志
docker logs -f singbox
```

### 2. 检查服务状态

```bash
# 进入容器
docker exec -it singbox bash

# 检查 supervisord 管理的服务
supervisorctl status

# 检查 sing-box 运行状态
ps aux | grep sing-box
```

### 3. 测试连接

```bash
# 从客户端测试 VMess 连接（假设服务端 IP 为 1.2.3.4）
# 使用客户端工具连接到 vmess://...

# 检查服务端日志
docker logs singbox | grep -i "accepted"
```

## 服务端配置说明

### 配置文件位置

服务端配置通常位于：
- `config/server-config.json` - 主配置文件
- `config/cert/` - TLS 证书目录（如果使用）

### 基本配置结构

```json
{
  "log": {
    "level": "info"
  },
  "inbounds": [
    {
      "type": "vmess",
      "tag": "vmess-in",
      "listen": "::",
      "listen_port": 8080,
      "users": [
        {
          "uuid": "your-uuid-here",
          "alterId": 0
        }
      ]
    },
    {
      "type": "trojan",
      "tag": "trojan-in",
      "listen": "::",
      "listen_port": 8443,
      "users": [
        {
          "password": "your-password-here"
        }
      ],
      "tls": {
        "enabled": true,
        "certificate_path": "/config/cert/fullchain.pem",
        "key_path": "/config/cert/privkey.pem"
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    },
    {
      "type": "block",
      "tag": "block"
    }
  ],
  "route": {
    "rules": [
      {
        "protocol": "dns",
        "outbound": "dns-out"
      },
      {
        "ip_is_private": true,
        "outbound": "block"
      }
    ]
  }
}
```

### 端口映射

在 `docker-compose.yml` 中配置：

```yaml
services:
  singbox:
    ports:
      - "8080:8080"   # VMess
      - "8443:8443"   # Trojan with TLS
      - "1080:1080"   # SOCKS5 (可选)
```

### 数据卷

```yaml
volumes:
  - /data/www/singbox/config:/config
  - /data/www/singbox/logs:/var/log/sing-box
  - /data/www/singbox/cert:/config/cert  # TLS 证书
```

### 环境变量

可在 `docker-compose.yml` 中设置：

```yaml
environment:
  - TZ=Asia/Shanghai
  - SING_BOX_LOG_LEVEL=info
```

### 安全配置

1. **修改默认 UUID 和密码**：
   ```bash
   # 生成新的 UUID
   uuidgen
   # 或使用在线工具
   ```

2. **启用 TLS**：
   - 使用 Let's Encrypt 或自签名证书
   - 配置证书路径

3. **限制访问**：
   - 使用防火墙规则
   - 配置 IP 白名单（在 sing-box 配置中）

### 更新服务端配置

```bash
# 编辑配置
vim config/server-config.json

# 重启服务
docker restart singbox

# 或重载配置（如果支持）
docker exec singbox supervisorctl restart sing-box
```

### 服务端故障排查

#### 连接被拒绝

```bash
# 检查端口是否监听
docker exec singbox netstat -tlnp | grep sing-box

# 检查防火墙
iptables -L -n | grep 8080

# 检查日志
docker logs singbox | tail -50
```

#### TLS 证书问题

```bash
# 验证证书
openssl x509 -in /data/www/singbox/cert/fullchain.pem -text -noout

# 检查证书权限
docker exec singbox ls -la /config/cert/
```

#### 服务无法启动

```bash
# 检查配置文件语法
docker exec singbox sing-box check -c /config/server-config.json

# 查看 supervisord 日志
docker exec singbox cat /var/log/supervisor/supervisord.log
```

## 安全建议

### 客户端

- 修改默认 API 密钥
- `9090`、`9191` 监听 `0.0.0.0`，应通过防火墙限制为可信局域网
- 不要把真实订阅 URL 或生成后含真实节点的 `config.json` 提交到公共仓库

### 服务端

- **强制修改默认凭证**：UUID、密码必须使用强随机值
- **启用 TLS**：生产环境必须使用 TLS 加密传输
- **限制访问源**：使用防火墙或 sing-box 规则限制客户端 IP
- **定期更新**：保持 sing-box 和系统更新到最新版本
- **日志审计**：定期检查访问日志，发现异常及时处理
- **端口隐藏**：不要使用默认端口，使用非标准端口并配置伪装

## 参考

- [sing-box 配置文档](https://sing-box.sagernet.org/zh/configuration/)
- [sing-box API](https://sing-box.sagernet.org/zh/configuration/service/api/)
- [zashboard](https://github.com/Zephyruso/zashboard)
- [规则集仓库](https://github.com/iflyelf/gwf)

## 许可证

MIT License
