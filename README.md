# singbox-docker

sing-box 客户端镜像与配置。客户端镜像只运行 sing-box 和 nginx，不包含服务端的 `supervisord`、VMess 入站或 Trojan 入站配置。

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

## 安全建议

- 修改默认 API 密钥
- `9090`、`9191` 监听 `0.0.0.0`，应通过防火墙限制为可信局域网
- 不要把真实订阅 URL 或生成后含真实节点的 `config.json` 提交到公共仓库

## 参考

- [sing-box 配置文档](https://sing-box.sagernet.org/zh/configuration/)
- [sing-box API](https://sing-box.sagernet.org/zh/configuration/service/api/)
- [zashboard](https://github.com/Zephyruso/zashboard)
- [规则集仓库](https://github.com/iflyelf/gwf)

## 许可证

MIT License
