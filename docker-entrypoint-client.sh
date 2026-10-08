#!/bin/bash

set -Eeuo pipefail

singbox_pid=""
nginx_pid=""

cleanup() {
    kill "${singbox_pid:-}" "${nginx_pid:-}" 2>/dev/null || true
    wait "${singbox_pid:-}" "${nginx_pid:-}" 2>/dev/null || true
}

trap cleanup INT TERM QUIT

/usr/bin/sing-box check -c /etc/sing-box/config.json

/usr/bin/sing-box run -c /etc/sing-box/config.json &
singbox_pid=$!

nginx -p /data/nginx -c /data/nginx/conf/nginx.conf -g 'daemon off;' &
nginx_pid=$!

status=0
wait -n "${singbox_pid}" "${nginx_pid}" || status=$?
cleanup
exit "${status}"
