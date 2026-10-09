# 订阅配置环境变量说明

sing-box 订阅更新脚本支持通过环境变量完全控制订阅配置，包括 URL、组名称和启用状态。

## 快速开始

### 方式 1: 单个订阅源

```bash
export CLASH_SUBSCRIPTION_URL='https://example.com/sub'
export CLASH_SUBSCRIPTION_TAG='myairport'
export CLASH_SUBSCRIPTION_ENABLED='true'

./update_subscription.sh
```

### 方式 2: 多个订阅源

```bash
# 订阅源 1
export CLASH_SUBSCRIPTION_URL_1='https://example1.com/sub'
export CLASH_SUBSCRIPTION_TAG_1='xiaonuo'
export CLASH_SUBSCRIPTION_ENABLED_1='true'

# 订阅源 2
export CLASH_SUBSCRIPTION_URL_2='https://example2.com/sub'
export CLASH_SUBSCRIPTION_TAG_2='airport2'
export CLASH_SUBSCRIPTION_ENABLED_2='true'

# 订阅源 3（临时禁用）
export CLASH_SUBSCRIPTION_URL_3='https://example3.com/sub'
export CLASH_SUBSCRIPTION_TAG_3='backup'
export CLASH_SUBSCRIPTION_ENABLED_3='false'

./update_subscription.sh
```

---

## 环境变量详解

### 基础订阅（单源）

| 环境变量 | 说明 | 必填 | 默认值 | 示例 |
|---------|------|------|--------|------|
| `CLASH_SUBSCRIPTION_URL` | 订阅地址 | ✅ | 无 | `https://sub.example.com/link` |
| `CLASH_SUBSCRIPTION_TAG` | 组名称/标签前缀 | ❌ | 空 | `myairport` |
| `CLASH_SUBSCRIPTION_ENABLED` | 启用状态 | ❌ | `true` | `true`/`false` |

### 多订阅源（编号）

支持 `_1`, `_2`, `_3` ... `_99` 后缀，最多 99 个订阅源。

| 环境变量 | 说明 | 必填 | 默认值 | 示例 |
|---------|------|------|--------|------|
| `CLASH_SUBSCRIPTION_URL_N` | 订阅地址 | ✅ | 无 | `https://sub.example.com/link` |
| `CLASH_SUBSCRIPTION_TAG_N` | 组名称/标签前缀 | ❌ | `airportN` | `xiaonuo` |
| `CLASH_SUBSCRIPTION_ENABLED_N` | 启用状态 | ❌ | `true` | `true`/`false` |

**N** 为订阅编号：1, 2, 3, ...

---

## 启用状态值

`CLASH_SUBSCRIPTION_ENABLED` 和 `CLASH_SUBSCRIPTION_ENABLED_N` 支持以下值：

| 值 | 结果 | 说明 |
|----|------|------|
| `true`, `1`, `yes`, `on` | 启用 ✅ | 订阅源会被使用 |
| `false`, `0`, `no`, `off` | 禁用 ❌ | 订阅源会被跳过 |
| 未设置 | 启用 ✅ | 默认启用 |

---

## 组名称（Tag）作用

组名称会作为节点名称的前缀，方便区分不同订阅源的节点。

### 示例

**配置**:
```bash
export CLASH_SUBSCRIPTION_TAG_1='xiaonuo'
```

**原始节点名**: `香港 01`  
**转换后**: `🎉 xiaonuo🛺香港 01`

**原始节点名**: `美国节点`  
**转换后**: `🎉 xiaonuo🛺美国节点`

---

## 完整示例

### 示例 1: Docker Compose

```yaml
version: '3.8'
services:
  singbox:
    image: swr.cn-east-3.myhuaweicloud.com/iflyelf/singbox-client:latest
    environment:
      # 主订阅
      - CLASH_SUBSCRIPTION_URL_1=https://xiaonuo.example.com/sub
      - CLASH_SUBSCRIPTION_TAG_1=xiaonuo
      - CLASH_SUBSCRIPTION_ENABLED_1=true
      
      # 备用订阅
      - CLASH_SUBSCRIPTION_URL_2=https://backup.example.com/sub
      - CLASH_SUBSCRIPTION_TAG_2=backup
      - CLASH_SUBSCRIPTION_ENABLED_2=false
      
      # 第三方机场
      - CLASH_SUBSCRIPTION_URL_3=https://airport.example.com/sub
      - CLASH_SUBSCRIPTION_TAG_3=airport3
      - CLASH_SUBSCRIPTION_ENABLED_3=true
    volumes:
      - ./conf:/etc/sing-box
```

### 示例 2: Shell 脚本

```bash
#!/bin/bash
# update_my_subscriptions.sh

# 主力订阅
export CLASH_SUBSCRIPTION_URL_1='https://xiaonuo.example.com/subscribe?token=xxx'
export CLASH_SUBSCRIPTION_TAG_1='xiaonuo'
export CLASH_SUBSCRIPTION_ENABLED_1='true'

# 备用订阅（当前禁用）
export CLASH_SUBSCRIPTION_URL_2='https://backup.example.com/subscribe?token=yyy'
export CLASH_SUBSCRIPTION_TAG_2='backup'
export CLASH_SUBSCRIPTION_ENABLED_2='false'

# 免费试用订阅
export CLASH_SUBSCRIPTION_URL_3='https://free.example.com/trial'
export CLASH_SUBSCRIPTION_TAG_3='free'
export CLASH_SUBSCRIPTION_ENABLED_3='true'

# 执行更新
cd /path/to/singbox-docker
./update_subscription.sh
```

### 示例 3: 环境变量文件

创建 `.env` 文件：

```bash
# .env
CLASH_SUBSCRIPTION_URL_1=https://xiaonuo.example.com/sub
CLASH_SUBSCRIPTION_TAG_1=xiaonuo
CLASH_SUBSCRIPTION_ENABLED_1=true

CLASH_SUBSCRIPTION_URL_2=https://airport.example.com/sub
CLASH_SUBSCRIPTION_TAG_2=airport2
CLASH_SUBSCRIPTION_ENABLED_2=true
```

使用：

```bash
# 加载环境变量
source .env
# 或
set -a && source .env && set +a

# 执行更新
./update_subscription.sh
```

---

## 高级用法

### 动态切换订阅源

```bash
#!/bin/bash
# 工作日使用订阅 1，周末使用订阅 2

day=$(date +%u)  # 1-7 (周一到周日)

if [ "$day" -le 5 ]; then
    # 周一到周五
    export CLASH_SUBSCRIPTION_URL_1='https://work.example.com/sub'
    export CLASH_SUBSCRIPTION_TAG_1='work'
    export CLASH_SUBSCRIPTION_ENABLED_1='true'
    
    export CLASH_SUBSCRIPTION_ENABLED_2='false'
else
    # 周末
    export CLASH_SUBSCRIPTION_ENABLED_1='false'
    
    export CLASH_SUBSCRIPTION_URL_2='https://home.example.com/sub'
    export CLASH_SUBSCRIPTION_TAG_2='home'
    export CLASH_SUBSCRIPTION_ENABLED_2='true'
fi

./update_subscription.sh
```

### 条件启用订阅

```bash
#!/bin/bash
# 根据流量使用情况自动切换订阅

remaining=$(get_traffic_remaining)  # 假设这是获取剩余流量的函数

if [ "$remaining" -lt 1000 ]; then
    # 主订阅流量不足，启用备用
    export CLASH_SUBSCRIPTION_ENABLED_1='false'
    export CLASH_SUBSCRIPTION_ENABLED_2='true'
    echo "主订阅流量不足，切换到备用订阅"
else
    export CLASH_SUBSCRIPTION_ENABLED_1='true'
    export CLASH_SUBSCRIPTION_ENABLED_2='false'
fi

./update_subscription.sh
```

---

## 优先级说明

配置的优先级从高到低：

1. **环境变量** (最高优先级)
   - `CLASH_SUBSCRIPTION_URL_N`
   - `CLASH_SUBSCRIPTION_TAG_N`
   - `CLASH_SUBSCRIPTION_ENABLED_N`

2. **配置文件 + 环境变量组合**
   - `config_with_sub.json` 中的 `sources[].url: "env:CLASH_SUBSCRIPTION_URL_1"`
   - 环境变量覆盖 `tag_prefix` 和 `enabled`

3. **纯配置文件**
   - `config_with_sub.json` 中的硬编码配置

**建议**: 使用环境变量方式，更灵活且易于管理。

---

## 故障排查

### 订阅未生效

检查环境变量是否正确设置：

```bash
echo "URL_1: ${CLASH_SUBSCRIPTION_URL_1}"
echo "TAG_1: ${CLASH_SUBSCRIPTION_TAG_1}"
echo "ENABLED_1: ${CLASH_SUBSCRIPTION_ENABLED_1}"
```

### 查看实际使用的订阅

运行脚本时会显示：

```
✓ 订阅源 1: tag=xiaonuo, enabled=true
✓ 订阅源 2: tag=backup, enabled=false
```

### 启用状态不生效

确保值为小写，且无前后空格：

```bash
# ✅ 正确
export CLASH_SUBSCRIPTION_ENABLED_1='true'

# ❌ 错误
export CLASH_SUBSCRIPTION_ENABLED_1='True'   # 大写
export CLASH_SUBSCRIPTION_ENABLED_1=' true'  # 有空格
```

---

## 常见问题

### Q: 最多支持多少个订阅源？

A: 最多支持 99 个订阅源（`_1` 到 `_99`）。

### Q: 可以只设置 URL，不设置 TAG 吗？

A: 可以。TAG 不是必填的，默认值为 `airportN`（N 为订阅编号）。

### Q: 环境变量会覆盖配置文件吗？

A: 是的。如果同时存在环境变量和配置文件，环境变量优先级更高。

### Q: 如何临时禁用某个订阅？

A: 设置 `CLASH_SUBSCRIPTION_ENABLED_N='false'` 即可。

---

## 相关文档

- [订阅更新脚本使用说明](../update_subscription.sh)
- [配置文件说明](../conf/config_with_sub.json)
- [Docker Compose 配置](../docker-compose-client.yml)
