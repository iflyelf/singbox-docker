# 多订阅源使用指南

## 功能特性

- ✅ 支持多个订阅 URL
- ✅ 每个订阅可指定标签前缀
- ✅ 节点自动分组
- ✅ 独立启用/禁用控制
- ✅ 兼容旧版单订阅格式

## 配置说明

### 1. 配置订阅源

编辑 `conf/config_with_sub.json`：

```json
{
  "_subscription": {
    "_comment": "订阅配置 - 支持多个订阅源",
    "sources": [
      {
        "url": "env:CLASH_SUBSCRIPTION_URL_1",
        "tag_prefix": "xiaonuo",
        "enabled": true
      },
      {
        "url": "env:CLASH_SUBSCRIPTION_URL_2",
        "tag_prefix": "airport2",
        "enabled": false
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

### 2. 设置环境变量

```bash
# xiaonuo 订阅
export CLASH_SUBSCRIPTION_URL_1='https://your-xiaonuo-subscription-url'

# 其他机场订阅
export CLASH_SUBSCRIPTION_URL_2='https://your-airport2-subscription-url'
```

### 3. 更新订阅

```bash
./update_subscription.sh
```

### 4. 重启容器

```bash
docker compose -f docker-compose-client.yml restart
```

## 节点分组规则

### 自动分组

订阅源的节点会自动添加标签前缀：

- **xiaonuo 订阅**（tag_prefix: `xiaonuo`）
  - 节点标签：`🎉 xiaonuo🛺节点名`
  - 自动加入 `🎉 xiaonuo` 代理组

- **airport2 订阅**（tag_prefix: `airport2`）
  - 节点标签：`🎉 airport2🛺节点名`
  - 自动加入 `🎉 airport2` 代理组

### 全局代理组

以下代理组包含**所有订阅源**的节点：
- `♻️ 自动选择`
- `🔯 故障转移`
- `🔮 负载均衡-轮询`
- `🔮 负载均衡-散列`
- `🌐 全部节点`

## 使用场景

### 场景 1：单一机场

```bash
# 只启用 xiaonuo 订阅
export CLASH_SUBSCRIPTION_URL_1='https://xiaonuo-sub-url'
./update_subscription.sh
```

### 场景 2：多机场混用

```bash
# 启用两个订阅源
export CLASH_SUBSCRIPTION_URL_1='https://xiaonuo-sub-url'
export CLASH_SUBSCRIPTION_URL_2='https://airport2-sub-url'

# 修改 config_with_sub.json，两个订阅都设置 enabled: true
# 然后更新
./update_subscription.sh
```

### 场景 3：临时禁用某个订阅

编辑 `conf/config_with_sub.json`，设置对应订阅的 `enabled: false`，然后重新更新：

```bash
./update_subscription.sh
```

## DNS 配置

**已彻底移除 sing-box DNS 配置！**

- ✅ 规则集下载使用系统 DNS（宿主机 smartdns）
- ✅ 用户流量直接走系统 DNS
- ✅ 零 DNS 查询延迟

## 兼容性

### 兼容旧版配置

如果使用旧版单订阅格式：

```bash
export CLASH_SUBSCRIPTION_URL='https://your-subscription-url'
./update_subscription.sh
```

脚本会自动兼容，节点不会添加前缀。

## 故障排查

### 订阅更新失败

```bash
# 检查环境变量
env | grep CLASH_SUBSCRIPTION_URL

# 手动测试订阅地址
curl -v "你的订阅地址"
```

### 节点未分组

检查 `config_with_sub.json` 中的 `tag_prefix` 是否与代理组名称匹配。

### 查看日志

```bash
docker logs -f singbox-client
```
