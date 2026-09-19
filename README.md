# nacos-demo

用 Spring Cloud Alibaba + Nacos 搭的功能验证工程，覆盖四件事：

1. **配置中心** —— 应用启动时从 Nacos 拉取配置
2. **配置动态刷新** —— Nacos 侧改配置，应用不重启即可生效
3. **服务注册与发现** —— 应用自动注册，并能查到其他服务的实例列表
4. **服务间调用 + 客户端负载均衡** —— 只写服务名调用，多个实例自动轮询

---

## 架构

```
                        ┌────────────────────────────┐
                        │        Nacos 服务端         │
   注册 / 订阅 ────────▶ │  :8848  HTTP API            │ ◀──────── 注册 / 订阅
                        │  :8081  控制台 UI            │
                        │  :9848 / :9849  gRPC        │
                        └────────────────────────────┘
                             ▲                  ▲
                 注册为 demo  │                  │  注册为 provider（两个实例）
                             │                  │
            ┌────────────────┴─────┐      ┌─────┴──────────────┐
            │  demo  （消费者）      │      │  provider  :8082   │
            │  :8080               │─────▶│  provider  :8083   │
            │  配置中心 + 服务发现   │      │  只负责提供服务      │
            └──────────────────────┘      └────────────────────┘
                     │
                     └── 调用写法：GET http://provider/greet
                         （写的是服务名，不是 IP:端口）
```

## 目录结构

```
nacos-demo/
├── pom.xml              # 父 pom：统一管理 Boot / Spring Cloud / SCA 版本
├── config.env           # ★ 端口、Nacos 地址等运行配置，改这里
├── README.md
├── start-all.sh         # 一键启动全部（含 Nacos）
├── stop-all.sh          # 一键停止
├── logs/                # 各应用运行日志
├── demo/                # 消费者
│   └── src/main/java/com/example/demo/
│       ├── DemoApplication.java     # 启动类
│       ├── HelloController.java     # /hello /info /config /services
│       └── CallController.java      # /call ← 服务间调用 + 负载均衡
├── provider/            # 服务提供者
│   └── src/main/java/com/example/provider/
│       ├── ProviderApplication.java
│       └── GreetController.java     # /greet
└── archive/
    └── before-nacos/    # 接入 Nacos 之前的原始工程备份
```

## 端口占用

以下是 `config.env` 里的默认值，**都可以改**。

| 端口 | 归属 | 说明 |
|---|---|---|
| 8080 | demo | 消费者 / 配置中心示例 |
| 8081 | Nacos | 控制台 UI（Nacos 3.x 默认 8080，已改到 8081 避让） |
| 8082 / 8083 | provider | 两个实例，用于观察负载均衡 |
| 8848 | Nacos | 主 HTTP API |
| 9848 / 9849 | Nacos | gRPC 长连接（固定等于 8848 + 1000 / +1001） |

## 快速开始

```bash
# 1. 构建（在 nacos-demo 目录下，会一次构建两个模块）
mvn clean package -DskipTests

# 2. 一键启动 Nacos + 两个 provider + demo
./start-all.sh

# 3. 一键停止（加 --with-nacos 连 Nacos 一起停）
./stop-all.sh
```

也可以手动逐个启动：

```bash
# Nacos（standalone 模式，内嵌 Derby，不需要额外装数据库）
~/.local/lib/nacos/bin/startup.sh -m standalone

# provider，想开几个实例就改端口开几个
java -jar provider/target/provider-1.0.0.jar --server.port=8082
java -jar provider/target/provider-1.0.0.jar --server.port=8083

# demo
java -jar demo/target/demo-1.0.0.jar
```

Nacos 控制台：<http://localhost:8081/next/>，账号 `nacos` / `nacos`

## 配置端口（config.env）

端口、Nacos 地址这些集中在根目录的 `config.env`，改完重新执行 `./start-all.sh` 即可，
**不需要重新构建**。

| 配置项 | 默认值 | 说明 |
|---|---|---|
| `DEMO_PORT` | `8080` | demo 监听端口 |
| `PROVIDER_PORTS` | `8082 8083` | provider 实例端口列表，空格分隔，**加几个端口就起几个实例** |
| `NACOS_SERVER_ADDR` | `127.0.0.1:8848` | Nacos 地址 |
| `NACOS_NAMESPACE` | `public` | 命名空间 |
| `NACOS_USERNAME` / `NACOS_PASSWORD` | `nacos` / `nacos` | 账号密码 |
| `NACOS_CONSOLE_PORT` | `8081` | 仅用于打印提示 |
| `NACOS_HOME` | `~/.local/lib/nacos` | Nacos 安装目录 |
| `JAVA_HOME` | `~/.local/lib/jdk` | JDK 目录 |

也可以不改文件，用环境变量临时覆盖：

```bash
# 换一套端口跑
DEMO_PORT=9080 PROVIDER_PORTS="9082 9083" ./start-all.sh

# 开三个 provider 实例
PROVIDER_PORTS="8082 8083 8084" ./start-all.sh
```

`start-all.sh` 会把 `config.env` 里的 Nacos 配置通过环境变量（Spring Boot 宽松绑定）传给应用，
所以 `application.properties` 里的那几个值只是「不通过脚本、直接跑 jar」时的默认值，
改配置时不用两个文件同步改。

## 验证清单

```bash
# 1) 配置中心：值是 Nacos 下发的
curl -s localhost:8080/config
# {"demo.greeting":"hello-from-nacos-v2","demo.version":"v2"}

# 2) 服务发现：能列出自己和 provider 的所有实例
curl -s localhost:8080/services
# {"demo":["<本机IP>:8080"],"provider":["<本机IP>:8082","<本机IP>:8083"]}

# 3) 服务间调用 + 负载均衡：连打几次，instance 会在 8082/8083 之间交替
curl -s localhost:8080/call
# {"call":"GET http://provider/greet?name=World",
#  "response":{"service":"provider","instance":"provider@8082", ...}}

# 4) Nacos 健康状态
curl -s localhost:8848/nacos/actuator/health
# {"status":"UP"}
```

**动态刷新验证**：到控制台「配置管理 → demo.yaml → 编辑」，把 `version` 从 `v2` 改成 `v3` 保存，
再刷 `curl -s localhost:8080/config`，约十几秒后会看到 `v3`，应用没有重启。

**负载均衡 / 故障转移验证**：停掉其中一个 provider，观察 `/call` 的 `instance` 字段变化，
再把它拉起来，会自动回到轮询队列。

## 配置说明

两个应用的 `src/main/resources/application.properties` 里，关键项是这几个：

```properties
# 注册到 Nacos 的服务名 —— 别的服务就用这个名字调用你
spring.application.name=demo

# Nacos 地址与账号
spring.cloud.nacos.server-addr=127.0.0.1:8848
spring.cloud.nacos.username=nacos
spring.cloud.nacos.password=nacos

# 命名空间：Nacos 3.x 的默认命名空间 id 是字面量 public，必须显式写
spring.cloud.nacos.discovery.namespace=public
spring.cloud.nacos.config.namespace=public

# 启动时从 Nacos 拉取 demo.yaml；optional: 前缀保证配置不存在时也能启动
spring.config.import=optional:nacos:demo.yaml?group=DEFAULT_GROUP&refreshEnabled=true
```

## 版本对应关系

| 组件 | 版本 | 备注 |
|---|---|---|
| Spring Boot | 4.0.8 | 被 Spring Cloud 2025.1.3 锁定，不能随意升到 4.1 |
| Spring Cloud | 2025.1.3 | 其 POM 中声明 `<spring-boot.version>4.0.8</spring-boot.version>` |
| Spring Cloud Alibaba | 2025.1.0.0 | |
| nacos-client | 3.1.1 | SCA 自带，与服务端同大版本 |
| Nacos 服务端 | 3.2.4 | 装在 `~/.local/lib/nacos` |
| JDK | 21.0.12.1 | 装在 `~/.local/lib/jdk` |
| Maven | 3.9.16 | 已配置阿里云镜像 `~/.m2/settings.xml` |

> 注意：目前还没有对齐 Spring Boot 4.1 的 Spring Cloud 发布，所以 Boot 锁在 4.0.8。
> 升级 Boot 前务必先确认 Spring Cloud 的配套版本。

## 踩坑记录

这些都是实际踩到并已规避的，改动前建议先看一遍。

**1. 命名空间必须显式写 `public`**
Nacos 3.x 的默认命名空间 id 是字面量字符串 `public`（不是 2.x 时代的空字符串）。
调用 v3 接口时不带 `namespaceId`，服务端不会回落到 `public`，直接报 `resource not found`。
所以 `discovery.namespace` 和 `config.namespace` 都显式写了 `public`。

**2. v1 接口在 Nacos 3.x 已移除**
`/nacos/v1/cs/configs`、`/nacos/v1/console/health/readiness` 这些全是 404，要改用 v3：

| 用途 | 接口 |
|---|---|
| 发布/查询配置（管理端，需登录 token） | `POST/GET /nacos/v3/admin/cs/config` |
| 读取配置（客户端） | `GET /nacos/v3/client/cs/config` |
| 查询实例列表 | `GET /nacos/v3/client/ns/instance/list` |
| 健康检查 | `GET /nacos/actuator/health` |

另外 v3 的参数名从 `group` 变成了 `groupName`。

**3. Nacos 3.x 控制台默认关闭，且默认端口是 8080**
`nacos.console.ui.enabled` 默认关闭，不开的话 8081 只返回一页提示。已改为 `true`。
控制台默认端口 8080 与 demo 冲突，已改到 8081。

**4. `startup.sh` 会交互式阻塞**
首次启动时 `nacos.core.auth.plugin.nacos.token.secret.key` 等三项为空，
`startup.sh` 里的 `process_required_config` 会执行 `read` 等你输入，表现为「命令卡住、Java 进程根本没起来」。
已在 `conf/application.properties` 里预填这三项。

**5. `@RefreshScope` 的刷新不是瞬时的**
实测从 Nacos 保存到应用生效约 12 秒（客户端长轮询推送）。不要以为没生效就反复重启。

**6. 客户端负载均衡有 35 秒缓存 —— 这是最容易误会的一个**
实例下线后，**Nacos 侧立刻就没有这个实例了，但调用方仍可能继续往它发请求并报 500**，
日志表现为 `Connect to <ip>:<port> failed: Connection refused`。

原因是两层缓存：

```
Nacos 服务端
   │ gRPC 推送（毫秒级）
   ▼
nacos-client 本地缓存            ← 第 1 层，更新很快
   │
   ▼
CachingServiceInstanceListSupplier ← 第 2 层，默认缓存 35 秒
   │
   ▼
RoundRobinLoadBalancer 挑实例
```

第 2 层的默认值（从 jar 里确认）：`spring.cloud.loadbalancer.cache.ttl = 35s`。
生产上建议开启重试兜住这个窗口：

```properties
spring.cloud.loadbalancer.retry.enabled=true
spring.cloud.loadbalancer.retry.retry-on-all-operations=true
```

## 运行时目录

除了工程目录，运行时还会在这些位置产生文件，排查问题时用得上：

| 路径 | 内容 |
|---|---|
| `./logs/` | 各应用（demo / provider）的启动日志 |
| `~/.local/lib/nacos/logs/` | Nacos 服务端日志，`startup.log` 是启动日志 |
| `~/logs/nacos/` | nacos-client 客户端日志 |
| `~/nacos/` | nacos-client 的**本地快照缓存**，分 `config/` 和 `naming/` |
| `~/.local/lib/nacos/data/` | Nacos 服务端数据（内嵌 Derby） |

`~/nacos/` 那两份快照值得知道：它保存了最近一次拉到的配置和实例列表，
所以**即使 Nacos 服务端挂了，应用仍能用快照启动**，不会直接起不来。

## 常见操作

```bash
# 加第三个 provider 实例：改 config.env 后重启
PROVIDER_PORTS="8082 8083 8084" ./start-all.sh

# 看某个应用日志
tail -f logs/demo.log

# 改完配置后重启全部应用（Nacos 会跳过，不会重开）
./stop-all.sh && ./start-all.sh

# 连 Nacos 一起停
./stop-all.sh --with-nacos
```
