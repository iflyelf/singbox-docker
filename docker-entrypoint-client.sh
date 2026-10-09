#!/bin/bash

set -Eeuo pipefail

# 挂载的静态配置（无订阅环境变量或订阅生成失败时使用）
STATIC_CONFIG="/etc/sing-box/config.json"
# 订阅模板：优先使用挂载的模板，不存在时使用镜像内置模板
TEMPLATE_FILE="${SUBSCRIPTION_TEMPLATE:-/etc/sing-box/config_with_sub.json}"
DEFAULT_TEMPLATE="/usr/local/share/singbox/config_with_sub.json"
CONFIG_MANAGER="/usr/local/share/singbox/config_manager.py"
# 运行时生成的配置写入容器内部可写目录，不修改挂载文件
RUNTIME_CONFIG="/etc/sing-box/runtime/config.json"

# 自动更新间隔（秒），默认 1 小时
AUTO_UPDATE_INTERVAL="${SUBSCRIPTION_UPDATE_INTERVAL:-3600}"

CONFIG_FILE="${STATIC_CONFIG}"

singbox_pid=""
nginx_pid=""
updater_pid=""

cleanup() {
    echo "正在停止服务..."
    kill "${singbox_pid:-}" "${nginx_pid:-}" "${updater_pid:-}" 2>/dev/null || true
    wait "${singbox_pid:-}" "${nginx_pid:-}" "${updater_pid:-}" 2>/dev/null || true
}

trap cleanup INT TERM QUIT

# 是否设置了 SUBSCRIPTION_URL 或 SUBSCRIPTION_URL_N（非空）
has_subscription_env() {
    local name
    for name in $(compgen -v SUBSCRIPTION_URL); do
        if [[ "${name}" =~ ^SUBSCRIPTION_URL(_[0-9]+)?$ ]] && [[ -n "${!name}" ]]; then
            return 0
        fi
    done
    return 1
}

generate_runtime_config() {
    local template="${TEMPLATE_FILE}"
    local tmp_config="${RUNTIME_CONFIG}.tmp"

    if [[ ! -f "${template}" ]]; then
        template="${DEFAULT_TEMPLATE}"
    fi

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 使用模板生成运行配置: ${template}"
    mkdir -p "$(dirname "${RUNTIME_CONFIG}")"
    rm -f "${tmp_config}"

    if python3 "${CONFIG_MANAGER}" "${template}" "${tmp_config}" once \
        && /usr/bin/sing-box check -c "${tmp_config}"; then
        mv -f "${tmp_config}" "${RUNTIME_CONFIG}"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✓ 订阅配置已生成: ${RUNTIME_CONFIG}"
        return 0
    fi

    rm -f "${tmp_config}"
    return 1
}

reload_singbox() {
    if [[ -n "${singbox_pid}" ]] && kill -0 "${singbox_pid}" 2>/dev/null; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] 向 sing-box 发送 HUP 信号重载配置..."
        kill -HUP "${singbox_pid}"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✓ 配置已重载"
    else
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ⚠️ sing-box 进程不存在，无法重载"
    fi
}

# 订阅自动更新后台任务
auto_update_subscription() {
    local interval="${AUTO_UPDATE_INTERVAL}"
    
    # 检查是否禁用自动更新
    if [[ "${SUBSCRIPTION_AUTO_UPDATE:-true}" =~ ^(false|0|no|off)$ ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] 订阅自动更新已禁用"
        return
    fi
    
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 启动订阅自动更新任务，间隔: ${interval}秒"
    
    while true; do
        sleep "${interval}"
        
        echo ""
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] 开始自动更新订阅..."
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        
        if generate_runtime_config; then
            reload_singbox
        else
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] ⚠️ 订阅更新失败，保持当前配置"
        fi
    done
}

# 初始化：检测订阅环境变量并生成配置
if has_subscription_env; then
    echo "检测到订阅环境变量"
    
    if ! generate_runtime_config; then
        if [[ -f "${RUNTIME_CONFIG}" ]]; then
            # 容器重启场景：保留上一次成功生成的订阅配置
            echo "⚠️ 订阅更新失败，使用上一次生成的配置: ${RUNTIME_CONFIG}"
            CONFIG_FILE="${RUNTIME_CONFIG}"
        else
            echo "⚠️ 订阅生成失败，回退到挂载配置: ${STATIC_CONFIG}"
        fi
    else
        CONFIG_FILE="${RUNTIME_CONFIG}"
    fi
fi

echo "使用配置: ${CONFIG_FILE}"
/usr/bin/sing-box check -c "${CONFIG_FILE}"

# 启动 sing-box
/usr/bin/sing-box run -c "${CONFIG_FILE}" &
singbox_pid=$!
echo "sing-box 已启动，PID: ${singbox_pid}"

# 启动 nginx
nginx -p /data/nginx -c /data/nginx/conf/nginx.conf -g 'daemon off;' &
nginx_pid=$!
echo "nginx 已启动，PID: ${nginx_pid}"

# 如果有订阅环境变量，启动自动更新后台任务
if has_subscription_env && [[ "${CONFIG_FILE}" == "${RUNTIME_CONFIG}" ]]; then
    auto_update_subscription &
    updater_pid=$!
    echo "订阅自动更新任务已启动，PID: ${updater_pid}"
fi

# 等待任意进程退出
status=0
wait -n "${singbox_pid}" "${nginx_pid}" "${updater_pid:-}" || status=$?
cleanup
exit "${status}"
