#!/usr/bin/env bash
#
# 一键启动 Nacos 验证环境。
# 端口、Nacos 地址等全部从同目录的 config.env 读取，也可用环境变量临时覆盖。
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

# 把 Nacos 配置通过环境变量传给应用（Spring Boot 宽松绑定），
# 这样不用改 application.properties，也不会出现在进程参数里
export SPRING_CLOUD_NACOS_SERVER_ADDR="$NACOS_SERVER_ADDR"
export SPRING_CLOUD_NACOS_USERNAME="$NACOS_USERNAME"
export SPRING_CLOUD_NACOS_PASSWORD="$NACOS_PASSWORD"
export SPRING_CLOUD_NACOS_DISCOVERY_NAMESPACE="$NACOS_NAMESPACE"
export SPRING_CLOUD_NACOS_CONFIG_NAMESPACE="$NACOS_NAMESPACE"

NACOS_HOST="${NACOS_SERVER_ADDR%%:*}"
NACOS_PORT="${NACOS_SERVER_ADDR##*:}"
read -ra PORTS <<< "$PROVIDER_PORTS"

# ---------------- 工具函数 ----------------
port_in_use() { ( exec 3<>"/dev/tcp/127.0.0.1/$1" ) 2>/dev/null; }

wait_http() {
  local url=$1 timeout=${2:-120} i
  for ((i = 0; i < timeout; i++)); do
    curl -sf -m 2 -o /dev/null "$url" && return 0
    sleep 1
  done
  return 1
}

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
  echo "找不到构建产物，请先在本目录执行: mvn clean package -DskipTests"
  exit 1
fi

echo "生效配置"
echo "  Nacos       $NACOS_SERVER_ADDR  (命名空间 $NACOS_NAMESPACE)"
echo "  demo        :$DEMO_PORT"
echo "  provider    ${PORTS[*]/#/:}"
echo

# ---------------- 1. Nacos ----------------
echo "[1/3] Nacos"
if port_in_use "$NACOS_PORT"; then
  echo "      $NACOS_SERVER_ADDR 已在运行，跳过"
else
  bash "$NACOS_HOME/bin/startup.sh" -m standalone < /dev/null > "$LOG_DIR/nacos-startup.out" 2>&1
  if wait_http "http://$NACOS_HOST:$NACOS_PORT/nacos/actuator/health" 180; then
    echo "      就绪"
  else
    echo "      启动失败，请查看 $NACOS_HOME/logs/startup.log"
    exit 1
  fi
fi

# ---------------- 2. provider ----------------
echo "[2/3] provider"
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

# ---------------- 3. demo ----------------
echo "[3/3] demo"
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
echo "  Nacos 控制台  http://localhost:$NACOS_CONSOLE_PORT/next/   账号 $NACOS_USERNAME / $NACOS_PASSWORD"
echo "  demo 接口     http://localhost:$DEMO_PORT/config  /services  /call"
for port in "${PORTS[@]}"; do
  echo "  provider 接口 http://localhost:$port/greet"
done
echo "  日志目录      $LOG_DIR"
