#!/usr/bin/env bash
#
# 启动本项目的应用（provider + demo）。
#
# 前提：Nacos 服务端已在运行。本项目只包含 Nacos 客户端，
#      不负责安装、启动或停止 Nacos 服务端。
#      服务端地址在 config.env 的 NACOS_SERVER_ADDR 里指定。
#
#   ./start-all.sh
#   DEMO_PORT=9000 PROVIDER_PORTS="9082 9083" ./start-all.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$ROOT/config.env"

LOG_DIR="$ROOT/logs"
PROVIDER_JAR="$ROOT/provider/target/provider-1.0.0.jar"
DEMO_JAR="$ROOT/demo/target/demo-1.0.0.jar"

export JAVA_HOME
mkdir -p "$LOG_DIR"

NACOS_HOST="${NACOS_SERVER_ADDR%%:*}"
NACOS_PORT="${NACOS_SERVER_ADDR##*:}"
read -ra PORTS <<< "$PROVIDER_PORTS"

# 把 Nacos 连接信息通过环境变量传给应用（Spring Boot 宽松绑定），
# 这样 application.properties 里的值只是「不走脚本、直接跑 jar」时的默认值
export SPRING_CLOUD_NACOS_SERVER_ADDR="$NACOS_SERVER_ADDR"
export SPRING_CLOUD_NACOS_USERNAME="$NACOS_USERNAME"
export SPRING_CLOUD_NACOS_PASSWORD="$NACOS_PASSWORD"
export SPRING_CLOUD_NACOS_DISCOVERY_NAMESPACE="$NACOS_NAMESPACE"
export SPRING_CLOUD_NACOS_CONFIG_NAMESPACE="$NACOS_NAMESPACE"

# ---------------- 工具函数 ----------------
port_in_use() { ( exec 3<>"/dev/tcp/127.0.0.1/$1" ) 2>/dev/null; }

wait_log() {
  local file=$1 pattern=$2 timeout=${3:-120} i
  for ((i = 0; i < timeout; i++)); do
    grep -q "$pattern" "$file" 2>/dev/null && return 0
    sleep 1
  done
  return 1
}

# ---------------- 前置检查 ----------------
if [[ ! -f "$PROVIDER_JAR" || ! -f "$DEMO_JAR" ]]; then
  echo "找不到构建产物，请先执行: mvn clean package -DskipTests"
  exit 1
fi

echo "生效配置"
echo "  Nacos       $NACOS_SERVER_ADDR  (命名空间 $NACOS_NAMESPACE)"
echo "  demo        :$DEMO_PORT"
echo "  provider    ${PORTS[*]/#/:}"
echo

# Nacos 是外部依赖，这里只检查可达性，不负责把它拉起来
if ! port_in_use "$NACOS_PORT"; then
  echo "错误：连接不上 Nacos —— $NACOS_SERVER_ADDR"
  echo
  echo "  本项目只包含 Nacos 客户端，服务端需要你自己准备好并保持运行。"
  echo "  · 如果 Nacos 在别的地址，改 config.env 里的 NACOS_SERVER_ADDR"
  echo "  · 如果 Nacos 还没起，请先启动它，再重新执行本脚本"
  exit 1
fi
if curl -sf -m 3 -o /dev/null "http://$NACOS_HOST:$NACOS_PORT/nacos/actuator/health"; then
  echo "Nacos 可达，健康检查通过"
else
  echo "Nacos 端口可达（健康接口未响应，不同版本路径可能不同，继续启动）"
fi
echo

# ---------------- 1. provider ----------------
echo "[1/2] provider"
for port in "${PORTS[@]}"; do
  if port_in_use "$port"; then
    echo "      :$port 已在运行，跳过"
    continue
  fi
  setsid nohup java -jar "$PROVIDER_JAR" --server.port="$port" \
    > "$LOG_DIR/provider-$port.log" 2>&1 < /dev/null &
  if wait_log "$LOG_DIR/provider-$port.log" "Started ProviderApplication" 180; then
    echo "      :$port 就绪"
  else
    echo "      :$port 启动失败，请查看 $LOG_DIR/provider-$port.log"
    exit 1
  fi
done

# ---------------- 2. demo ----------------
echo "[2/2] demo"
if port_in_use "$DEMO_PORT"; then
  echo "      :$DEMO_PORT 已在运行，跳过"
else
  setsid nohup java -jar "$DEMO_JAR" --server.port="$DEMO_PORT" \
    > "$LOG_DIR/demo.log" 2>&1 < /dev/null &
  if wait_log "$LOG_DIR/demo.log" "Started DemoApplication" 180; then
    echo "      :$DEMO_PORT 就绪"
  else
    echo "      启动失败，请查看 $LOG_DIR/demo.log"
    exit 1
  fi
fi

echo
echo "全部就绪"
echo "  demo 接口     http://localhost:$DEMO_PORT/config  /services  /call"
for port in "${PORTS[@]}"; do
  echo "  provider 接口 http://localhost:$port/greet"
done
echo "  Nacos 控制台  http://localhost:$NACOS_CONSOLE_PORT/next/   账号 $NACOS_USERNAME / $NACOS_PASSWORD"
echo "  日志目录      $LOG_DIR"
