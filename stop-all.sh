#!/usr/bin/env bash
#
# 停止本项目的应用（provider + demo）。
# 不涉及 Nacos 服务端 —— 它是外部依赖，本项目不负责启停。
#
#   ./stop-all.sh
#
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$ROOT/config.env"
read -ra PORTS <<< "$PROVIDER_PORTS"

export JAVA_HOME

port_in_use() { ( exec 3<>"/dev/tcp/127.0.0.1/$1" ) 2>/dev/null; }

# JVM 收到 TERM 后要优雅停机（注销 Nacos 注册、关闭连接池），端口不会立刻释放，
# 所以轮询等待而不是固定 sleep。
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

echo
echo "本项目端口状态:"
busy=0
for p in "$DEMO_PORT" "${PORTS[@]}"; do
  if port_in_use "$p"; then
    echo "  :$p 仍在监听"
    busy=1
  fi
done
[[ "$busy" == 0 ]] && echo "  （已全部释放）"
exit 0
