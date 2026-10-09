#############################################################################
#  sing-box 多阶段构建
#  - builder(编译阶段) = iflyelf/ubuntu:latest
#      已预装 Go / build-essential 等完整工具链, 无需再装 Go 与庞大依赖列表,
#      直接交叉编译 sing-box 静态二进制(CGO_ENABLED=0), 构建更快更稳。
#  - runtime(运行阶段) = iflyelf/ubuntu:lite
#      sing-box 为静态二进制, 运行阶段仅需 supervisor/iptables/ca-certificates,
#      镜像更小。
#############################################################################

# 在 BUILDPLATFORM 上交叉编译, 避免 QEMU 跑 Go 编译(极慢)
FROM --platform=$BUILDPLATFORM iflyelf/ubuntu:latest AS builder

LABEL maintainer="iflyelf"

# 时区/语言
ARG TZ=Asia/Shanghai
ENV TZ=$TZ
ARG LANG=zh_CN.UTF-8
ENV LANG=$LANG

# 交叉编译目标(buildx 自动注入)
ARG TARGETOS TARGETARCH
ARG GO111MODULE=on
ENV GO111MODULE=$GO111MODULE
ARG CGO_ENABLED=0
ENV CGO_ENABLED=$CGO_ENABLED
ENV GOOS=$TARGETOS
ENV GOARCH=$TARGETARCH

# SINGBOX 版本(由 update-version 工作流自动更新)
ARG SINGBOX_VERSION=v1.14.3
ENV SINGBOX_VERSION=$SINGBOX_VERSION

# ***** 克隆源码并交叉编译静态二进制 *****
# iflyelf/ubuntu:latest 已含 go 与 git, 无需再装依赖或安装 Go。
# 注意: 基础镜像 Go 版本可能高于 sing-box 要求(如 Go 1.27), 而 sing-box 依赖的
# go-json-experiment 在过高 Go 版本下会报 "undefined: json.SkipFunc" 等编译错误。
# 因 GOTOOLCHAIN=auto 只会向上满足 go.mod(不会降级), 故从 go.mod 读取其声明的
# Go 版本并用 GOTOOLCHAIN 精确锁定, 让 go 自动拉取匹配的工具链, 保证兼容。
RUN --mount=type=cache,target=/root/.cache/go-build \
   --mount=type=cache,target=/opt/golang/pkg/mod \
   set -eux && \
   go version && \
   git clone -b $SINGBOX_VERSION --depth 1 --progress https://github.com/SagerNet/sing-box.git /src && \
   cd /src && \
   # 读取 sing-box go.mod 声明的 Go 版本, 精确锁定工具链(避免过高 Go 破坏兼容)
   GOVER=$(grep -oP '^go \K[0-9]+\.[0-9]+(\.[0-9]+)?' go.mod | head -1) && \
   # 规范化为合法工具链名: go.mod 的 major.minor(如 1.26) 需补 .0 才是有效工具链版本
   case "$GOVER" in *.*.*) GOTOOLCHAIN=go${GOVER} ;; *.*) GOTOOLCHAIN=go${GOVER}.0 ;; esac && \
   export GOTOOLCHAIN && \
   echo "sing-box 要求 Go ${GOVER}, 锁定 GOTOOLCHAIN=${GOTOOLCHAIN}" && \
   go version && \
   export COMMIT=$(git rev-parse --short HEAD) && \
   export VERSION=$(go run ./cmd/internal/read_tag) && \
   go env -w GO111MODULE=on && \
   go env -w CGO_ENABLED=0 && \
   go mod download && \
   mkdir -p /go/bin && \
   go build -v -trimpath -tags 'with_gvisor,with_quic,with_dhcp,with_wireguard,with_utls,with_acme,with_clash_api,with_tailscale,with_ccm,with_ocm,badlinkname,tfogo_checklinkname0' \
        -o /go/bin/sing-box \
        -ldflags "-s -buildid= -X \"github.com/sagernet/sing-box/constant.Version=$VERSION\" -checklinkname=0" \
        ./cmd/sing-box && \
   ls -lh /go/bin/sing-box


##########################################
#         运行阶段 (runtime)              #
##########################################
FROM iflyelf/ubuntu:lite

LABEL maintainer="iflyelf" \
      org.opencontainers.image.description="sing-box, runtime on ubuntu:lite"

# 时区设置
ARG TZ=Asia/Shanghai
ENV TZ=$TZ
# 语言设置
ARG LANG=zh_CN.UTF-8
ENV LANG=$LANG

# 环境设置
ARG DEBIAN_FRONTEND=noninteractive
ENV DEBIAN_FRONTEND=$DEBIAN_FRONTEND

# 镜像变量
ARG DOCKER_IMAGE=iflyelf/sing-box
ENV DOCKER_IMAGE=$DOCKER_IMAGE

# ***** 运行阶段按需依赖 *****
# sing-box 为静态二进制(CGO_ENABLED=0), 无动态库依赖。
#   supervisor      -> 进程守护(同时管理 vmess/trojan 等多个 inbound)
#   iptables        -> tun/透明代理场景
#   ca-certificates -> ACME/TLS 根证书
ARG RUNTIME_DEPS="\
    supervisor \
    iptables \
    ca-certificates"
ENV RUNTIME_DEPS=$RUNTIME_DEPS

# ***** 安装运行依赖 *****
RUN set -eux && \
   # 更新系统软件
   DEBIAN_FRONTEND=noninteractive apt-get update -qqy && apt-get upgrade -qqy && \
   # 安装运行依赖包
   DEBIAN_FRONTEND=noninteractive apt-get install -qqy --no-install-recommends $RUNTIME_DEPS --option=Dpkg::Options::=--force-confdef && \
   # 验证依赖包是否真正安装成功(逐个检查 dpkg 状态, 缺失则构建失败)
   for pkg in $RUNTIME_DEPS; do \
       if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"; then \
           echo "ERROR: 运行依赖未成功安装: $pkg" >&2 && exit 1; \
       fi; \
   done && \
   echo "运行依赖验证通过" && \
   DEBIAN_FRONTEND=noninteractive apt-get -qqy autoremove --purge && \
   DEBIAN_FRONTEND=noninteractive apt-get -qqy autoclean && \
   rm -rf /var/lib/apt/lists/* /var/cache/apt/* /tmp/* && \
   # 更新时区
   ln -sf /usr/share/zoneinfo/${TZ} /etc/localtime && \
   echo ${TZ} > /etc/timezone

# 拷贝 sing-box 二进制
COPY --from=builder /go/bin/sing-box /usr/bin/sing-box

# 拷贝入口脚本与配置
COPY ["./docker-entrypoint.sh", "/usr/bin/"]
COPY ["./conf/sing-box", "/etc/sing-box"]
COPY ["./conf/supervisor", "/etc/supervisor"]

# 授予文件权限
RUN set -eux && \
    mkdir -p /etc/sing-box && \
    chmod a+x /usr/bin/docker-entrypoint.sh /usr/bin/sing-box && \
    # smoke test: 校验二进制可执行
    sing-box version

# 容器信号处理
STOPSIGNAL SIGQUIT

# ***** 入口(tini 作为 init, 优雅处理信号) *****
ENTRYPOINT ["/usr/bin/tini", "--", "docker-entrypoint.sh"]
