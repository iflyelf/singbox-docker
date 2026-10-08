# sing-box 客户端部署指南

## 快速开始

### 1. 启动容器

```bash
# 使用客户端 docker-compose
docker-compose -f docker-compose-client.yml up -d

# 查看日志
docker logs -f singbox-client
```

### 2. 更新订阅

```bash
# 设置订阅地址
export CLASH_SUBSCRIPTION_URL='你的订阅地址'

# 更新订阅（会自动重载配置）
./update_subscription.sh
```

### 3. 手动重载配置

```bash
# 方式 1: 使用重载脚本（推荐）
./reload_config.sh

# 方式 2: 重启容器
docker-compose -f docker-compose-client.yml restart

# 方式 3: 发送信号
docker exec singbox-client kill -HUP 1
```

## 配置说明

### docker-compose-client.yml

```yaml
version: '3.9'

services:
  singbox:
    # 华为云镜像（国内加速）
    image: swr.cn-east-3.myhuaweicloud.com/iflyelf/sing-box:latest
    container_name: singbox-client
    restart: unless-stopped
    
    # host 网络模式（性能最好）
    network_mode: host
    
    # 挂载配置文件（只读）
    volumes:
      - ./conf/config.json:/etc/sing-box/config.json:ro
```

**特点**:
- ✅ 配置文件挂载（支持热更新）
- ✅ host 网络模式（无需端口映射）
- ✅ 只读挂载（安全）
- ✅ 自动重启

## 实时生效机制

### 工作流程

```
更新订阅 → 修改 config.json → 发送 SIGHUP 信号 → sing-box 重载配置 ✅
```

### 详细说明

1. **配置文件挂载**
   - 宿主机: `./conf/config.json`
   - 容器内: `/etc/sing-box/config.json`
   - 修改宿主机文件，容器内立即可见

2. **配置重载**
   - 发送 `SIGHUP` 信号给 PID 1
   - sing-box 重新读取配置文件
   - 无需重启容器

3. **自动化流程**
   - `update_subscription.sh` 自动检测容器
   - 更新成功后自动调用 `reload_config.sh`
   - 无需手动干预

## 使用场景

### 场景 1: 手动更新订阅

```bash
export CLASH_SUBSCRIPTION_URL='订阅地址'
./update_subscription.sh

# 输出:
# ✓ 订阅更新成功
# ✓ 检测到 Docker 容器运行中
# ✓ 已发送 SIGHUP 信号
# ✅ 配置重载完成
```

### 场景 2: 定时自动更新

```bash
# 添加 crontab
crontab -e

# 每小时更新一次
0 * * * * export CLASH_SUBSCRIPTION_URL='订阅地址' && cd /path/to/singbox-docker && ./update_subscription.sh >> /var/log/singbox-update.log 2>&1
```

### 场景 3: 手动修改配置

```bash
# 1. 编辑配置文件
vim conf/config.json

# 2. 验证配置
sing-box check -c conf/config.json

# 3. 重载配置
./reload_config.sh
```

## 常用命令

```bash
# 启动服务
docker-compose -f docker-compose-client.yml up -d

# 停止服务
docker-compose -f docker-compose-client.yml down

# 重启服务
docker-compose -f docker-compose-client.yml restart

# 查看日志
docker logs -f singbox-client

# 查看实时日志（最后100行）
docker logs --tail 100 -f singbox-client

# 进入容器
docker exec -it singbox-client sh

# 检查配置
sing-box check -c conf/config.json

# 更新订阅
./update_subscription.sh

# 重载配置
./reload_config.sh
```

## 端口访问

由于使用 `host` 网络模式，所有端口直接监听在宿主机：

| 端口 | 服务 | 访问方式 |
|------|------|----------|
| 7890 | Mixed | `http://localhost:7890` |
| 7891 | SOCKS | `socks5://localhost:7891` |
| 7893 | TProxy | 透明代理 |
| 9090 | Clash API | `http://localhost:9090` |
| 9191 | sing-box API | `http://localhost:9191` |

### 局域网访问

替换 `localhost` 为服务器 IP：

```bash
# Clash API
http://192.168.1.100:9090

# sing-box API  
http://192.168.1.100:9191
```

## 故障排查

### 容器无法启动

```bash
# 检查日志
docker logs singbox-client

# 检查配置
sing-box check -c conf/config.json

# 检查端口占用
netstat -tlnp | grep -E '7890|7891|9090|9191'
```

### 配置重载失败

```bash
# 检查容器状态
docker ps | grep singbox-client

# 手动重启
docker-compose -f docker-compose-client.yml restart

# 查看错误日志
docker logs --tail 50 singbox-client
```

### 订阅更新失败

```bash
# 手动运行检查错误
export CLASH_SUBSCRIPTION_URL='订阅地址'
./update_subscription.sh

# 检查网络
ping raw.githubusercontent.com

# 使用 Docker 测试
docker run --rm -it \
  -e CLASH_SUBSCRIPTION_URL='订阅地址' \
  -v $(pwd):/app \
  -w /app \
  swr.cn-east-3.myhuaweicloud.com/iflyelf/sing-box:latest \
  python3 scripts/config_manager.py conf/config_with_sub.json conf/config.json once
```

## 性能优化

### 1. 使用 host 网络

已在 `docker-compose-client.yml` 中配置，无需额外设置。

### 2. 日志限制

```yaml
logging:
  driver: "json-file"
  options:
    max-size: "10m"  # 单个日志文件最大 10MB
    max-file: "3"    # 最多保留 3 个日志文件
```

### 3. 资源限制（可选）

如需限制资源使用，可添加：

```yaml
services:
  singbox:
    deploy:
      resources:
        limits:
          cpus: '1'
          memory: 512M
```

## 与服务端对比

| 项目 | 服务端 (docker-compose.yml) | 客户端 (docker-compose-client.yml) |
|------|----------------------------|-------------------------------------|
| 用途 | 服务器部署 | 个人客户端 |
| 网络模式 | bridge | host |
| 配置挂载 | 无 | ✅ 支持 |
| 热重载 | ❌ | ✅ 支持 |
| 复杂度 | 高（包含其他服务） | 低（仅 sing-box） |
| 推荐场景 | 服务器、旁路由 | 个人电脑、开发环境 |

## 安全建议

1. **配置文件权限**
   ```bash
   chmod 600 conf/config.json
   ```

2. **修改 API 密钥**
   编辑 `conf/config.json`，修改：
   ```json
   "secret": "@your-custom-secret"
   ```

3. **防火墙规则**
   ```bash
   # 仅允许局域网访问 API
   sudo ufw allow from 192.168.1.0/24 to any port 9090
   sudo ufw allow from 192.168.1.0/24 to any port 9191
   ```

## 相关文档

- [README.md](README.md) - 项目总览
- [CONFIG.md](CONFIG.md) - 配置详解
- [RULESET.md](RULESET.md) - 规则集管理
- [sing-box 官方文档](https://sing-box.sagernet.org/zh/)

## 更新日志

- 2024-10-08: 创建客户端部署方案
- 支持配置文件挂载和热重载
- 自动化订阅更新和配置重载
