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

### 2. 更新订阅

#### 单订阅源（兼容模式）

```bash
export CLASH_SUBSCRIPTION_URL='你的订阅地址'
./update_subscription.sh
```

#### 多订阅源（推荐）

先编辑 `conf/config_with_sub.json`：

```json
{
  "_subscription": {
    "sources": [
      {
        "url": "env:CLASH_SUBSCRIPTION_URL_1",
        "tag_prefix": "xiaonuo",
        "enabled": true
      },
      {
        "url": "env:CLASH_SUBSCRIPTION_URL_2",
        "tag_prefix": "airport2",
        "enabled": true
      }
    ],
    "update_interval": 3600,
    "auto_update": true,
    "user_agent": "clash"
  }
}
```

**参数说明：**
- `url`: 订阅地址，支持 `env:变量名` 格式
- `tag_prefix`: 标签前缀，用于区分不同订阅源的节点
- `enabled`: 是否启用该订阅源

然后设置环境变量并更新：

```bash
# 设置多个订阅地址
export CLASH_SUBSCRIPTION_URL_1='https://xiaonuo-订阅地址'
export CLASH_SUBSCRIPTION_URL_2='https://其他机场订阅地址'

# 更新订阅
./update_subscription.sh
```

**节点分组规则：**

- **xiaonuo 订阅**：节点标签 `🎉 xiaonuo🛺节点名`，自动加入 `🎉 xiaonuo` 组
- **airport2 订阅**：节点标签 `🎉 airport2🛺节点名`，自动加入 `🎉 airport2` 组
- **全局代理组**：`♻️ 自动选择`、`🔯 故障转移`、`🔮 负载均衡` 等包含所有订阅源的节点

脚本会：

1. 通过华为云 `singbox-client` 镜像运行 `scripts/config_manager.py`
2. 从 `conf/config_with_sub.json` 生成 `conf/config.json`
3. 生成失败时恢复备份
4. 检测到客户端容器后重启该容器，确保新配置完整生效

`_subscription` 是转换工具使用的元数据，不是 sing-box 原生字段，因此不能直接交给 sing-box 运行。运行时始终使用 `conf/config.json`。

### 3. 重新加载配置

```bash
./reload_config.sh
```

脚本会重启 `singbox-client` 容器。配置文件已挂载到容器内，重启后会完整加载新配置。

## 管理界面与 API

| 服务 | 地址 | 用途 |
|------|------|------|
| zashboard | `http://<服务器IP>:9898` | 通过 Clash API 管理节点 |
| Clash API | `http://<服务器IP>:9090` | 节点切换、延迟测试、连接管理 |
| sing-box API | `http://<服务器IP>:9191` | 原生 gRPC/gRPC-Web API |

默认 API 密钥：

```text
@admin123
```

zashboard 首次打开后填写：

- API 地址：`http://<服务器IP>:9090`
- Secret：`@admin123`

客户端镜像构建时已经打包 zashboard，不会在容器启动时从 GitHub 下载。

## 代理端口

| 端口 | 类型 |
|------|------|
| `7890` | Mixed（HTTP + SOCKS5） |
| `7891` | SOCKS5 |
| `7893` | TProxy |
| `9090` | Clash API |
| `9191` | sing-box API |
| `9898` | zashboard |

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

# 单订阅更新
export CLASH_SUBSCRIPTION_URL='你的订阅地址'
./update_subscription.sh

# 多订阅更新
export CLASH_SUBSCRIPTION_URL_1='xiaonuo订阅地址'
export CLASH_SUBSCRIPTION_URL_2='其他机场订阅地址'
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
env | grep CLASH_SUBSCRIPTION_URL

# 手动测试订阅地址
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
