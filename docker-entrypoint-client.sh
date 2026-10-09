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

CONFIG_FILE="${STATIC_CONFIG}"

singbox_pid=""
nginx_pid=""

cleanup() {
    kill "${singbox_pid:-}" "${nginx_pid:-}" 2>/dev/null || true
    wait "${singbox_pid:-}" "${nginx_pid:-}" 2>/dev/null || true
}

trap cleanup INT TERM QUIT

# 是否设置了 CLASH_SUBSCRIPTION_URL 或 CLASH_SUBSCRIPTION_URL_N（非空）
has_subscription_env() {
    local name
    for name in $(compgen -v CLASH_SUBSCRIPTION_URL); do
        if [[ "${name}" =~ ^CLASH_SUBSCRIPTION_URL(_[0-9]+)?$ ]] && [[ -n "${!name}" ]]; then
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

    echo "检测到订阅环境变量，使用模板生成运行配置: ${template}"
    mkdir -p "$(dirname "${RUNTIME_CONFIG}")"
    rm -f "${tmp_config}"

    if python3 "${CONFIG_MANAGER}" "${template}" "${tmp_config}" once \
        && /usr/bin/sing-box check -c "${tmp_config}"; then
        mv -f "${tmp_config}" "${RUNTIME_CONFIG}"
        CONFIG_FILE="${RUNTIME_CONFIG}"
        echo "✓ 订阅配置已生成: ${RUNTIME_CONFIG}"
        return 0
    fi

    rm -f "${tmp_config}"
    return 1
}

if has_subscription_env; then
    if ! generate_runtime_config; then
        if [[ -f "${RUNTIME_CONFIG}" ]]; then
            # 容器重启场景：保留上一次成功生成的订阅配置
            echo "⚠️ 订阅更新失败，使用上一次生成的配置: ${RUNTIME_CONFIG}"
            CONFIG_FILE="${RUNTIME_CONFIG}"
        else
            echo "⚠️ 订阅生成失败，回退到挂载配置: ${STATIC_CONFIG}"
        fi
    fi
fi

echo "使用配置: ${CONFIG_FILE}"
/usr/bin/sing-box check -c "${CONFIG_FILE}"

/usr/bin/sing-box run -c "${CONFIG_FILE}" &
singbox_pid=$!

nginx -p /data/nginx -c /data/nginx/conf/nginx.conf -g 'daemon off;' &
nginx_pid=$!

status=0
wait -n "${singbox_pid}" "${nginx_pid}" || status=$?
cleanup
exit "${status}"
