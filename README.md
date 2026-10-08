# singbox-docker

sing-box 客户端镜像与配置。客户端镜像只运行 sing-box 和 nginx，不包含服务端的 `supervisord`、VMess 入站或 Trojan 入站配置。

## 功能

- 使用最新稳定版 sing-box，构建时通过 GitHub API 获取版本
- 使用 `iflyelf/nginx:latest` 提供 nginx 运行产物
- 内置 zashboard，由 nginx 在 `9898` 端口提供
- Clash API 监听 `0.0.0.0:9090`
- sing-box 原生 API 监听 `0.0.0.0:9191`
- Mixed、SOCKS5、TProxy 分别监听 `7890`、`7891`、`7893`
- DNS 不由 sing-box 处理，直接使用外部 smartdns
- 使用远程 SRS 规则集
- 支持将 Clash 订阅转换为 sing-box 节点配置

## 镜像

国内推荐使用华为云 SWR：

```text
swr.cn-east-3.myhuaweicloud.com/iflyelf/singbox-client:latest
```

DockerHub：

```text
iflyelf/singbox-client:latest
```

## 文件结构

```text
singbox-docker/
├── Dockerfile                    # 原服务端镜像，不做改动
├── Dockerfile.client             # 客户端专用镜像
├── docker-entrypoint-client.sh   # 客户端入口，只启动 sing-box 和 nginx
├── docker-compose.yml            # 原服务端编排，不做改动
├── docker-compose-client.yml     # 客户端编排
├── conf/
│   ├── config.json               # sing-box 运行配置
│   ├── config_with_sub.json      # 带订阅元数据的配置模板
│   └── nginx-client/
│       └── vhost/default.conf    # zashboard，监听 9898
├── scripts/
│   ├── config_manager.py
│   ├── subscription_converter.py
│   └── auto_update_subscription.sh
├── update_subscription.sh
├── reload_config.sh
└── singbox-ruleset.sh
```

## 构建客户端镜像

```bash
docker build \
  -f Dockerfile.client \
  --build-arg SINGBOX_VERSION=v1.14.2 \
  -t singbox-client:latest \
  .
```

GitHub Actions 工作流 `.github/workflows/docker-publish-client.yml` 会自动获取最新稳定版 sing-box，构建 `linux/amd64`、`linux/arm64` 镜像并发布到 DockerHub 和华为云 SWR。

## 启动客户端

```bash
docker compose -f docker-compose-client.yml pull
docker compose -f docker-compose-client.yml up -d
docker logs -f singbox-client
```

客户端编排使用 `host` 网络、TUN 设备和所需内核挂载。原服务端 `docker-compose.yml` 不受影响。

## 更新订阅

订阅地址只通过环境变量传入，不写入仓库：

```bash
export CLASH_SUBSCRIPTION_URL='你的订阅地址'
./update_subscription.sh
```

脚本可从任意工作目录执行，它会：

1. 通过华为云 `singbox-client` 镜像运行 `scripts/config_manager.py`
2. 从 `conf/config_with_sub.json` 生成 `conf/config.json`
3. 生成失败时恢复备份
4. 检测到客户端容器后重启该容器，确保新配置完整生效

`config_with_sub.json` 中的订阅元数据如下：

```json
{
  "_subscription": {
    "url": "env:CLASH_SUBSCRIPTION_URL",
    "update_interval": 3600,
    "auto_update": true,
    "user_agent": "clash"
  }
}
```

`_subscription` 是转换工具使用的元数据，不是 sing-box 原生字段，因此不能直接交给 sing-box 运行。运行时始终使用 `conf/config.json`。

## 重新加载配置

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

## 规则集

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

# 更新订阅并重启加载
export CLASH_SUBSCRIPTION_URL='你的订阅地址'
./update_subscription.sh

# 停止
docker compose -f docker-compose-client.yml down
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
