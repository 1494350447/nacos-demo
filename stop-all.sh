#!/usr/bin/env bash
#
# 停止 Nacos 验证环境中的应用（端口配置从 config.env 读取，与 start-all.sh 保持一致）
#
#   ./stop-all.sh               只停 provider 和 demo
#   ./stop-all.sh --with-nacos  连 Nacos 服务端一起停
#
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$ROOT/config.env"
read -ra PORTS <<< "$PROVIDER_PORTS"

export JAVA_HOME

port_in_use() { ( exec 3<>"/dev/tcp/127.0.0.1/$1" ) 2>/dev/null; }

# JVM 收到 TERM 后要优雅停机（注销 Nacos 注册、关闭连接池），端口不会立刻释放，
# 所以这里轮询等待，而不是固定 sleep。
wait_port_free() {
  local port=$1 timeout=${2:-40} i
  for ((i = 0; i < timeout; i++)); do
    port_in_use "$port" || return 0
    sleep 1
  done
  return 1
}

stopped=0

stop_by_pattern() {
  local pattern=$1 label=$2
  if pkill -f "$pattern" 2>/dev/null; then
    echo "  已发送停止信号: $label"
    stopped=1
  else
    echo "  $label 未在运行"
  fi
}

stop_by_pattern 'provider-1\.0\.0\.jar' 'provider 实例'
stop_by_pattern 'demo-1\.0\.0\.jar' 'demo'

if [[ "$stopped" == 1 ]]; then
  echo "  等待端口释放 ..."
  for p in "$DEMO_PORT" "${PORTS[@]}"; do
    if wait_port_free "$p"; then
      echo "    :$p 已释放"
    else
      echo "    :$p 仍在占用（可稍后重试或手动检查）"
    fi
  done
fi

if [[ "${1:-}" == "--with-nacos" ]]; then
  echo "  停止 Nacos ..."
  bash "$NACOS_HOME/bin/shutdown.sh" > /dev/null 2>&1 || true
  if wait_port_free "${NACOS_SERVER_ADDR##*:}" 60; then
    echo "    Nacos 已停止"
  else
    echo "    Nacos 端口仍被占用"
  fi
fi

echo
echo "仍在监听的端口:"
busy=0
for p in "$DEMO_PORT" "${PORTS[@]}" "${NACOS_SERVER_ADDR##*:}" "$NACOS_CONSOLE_PORT"; do
  if port_in_use "$p"; then
    echo "  :$p"
    busy=1
  fi
done
[[ "$busy" == 0 ]] && echo "  （无，已全部释放）"
exit 0
