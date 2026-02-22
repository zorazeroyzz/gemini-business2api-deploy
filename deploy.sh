#!/bin/bash
set -e

# ============================================================
# Gemini Business2API 一键部署脚本
# 适用于 OpenCloudOS 9.4 / CentOS 9 / RHEL 9 系列
# ============================================================

DEPLOY_DIR="/opt/gemini-business2api"
CLASH_DIR="/opt/clash"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "🚀 Gemini Business2API 一键部署"
echo "================================"

# ---- 1. 检查 Docker ----
echo ""
echo "📦 [1/6] 检查 Docker..."
if ! command -v docker &>/dev/null; then
    echo "  Docker 未安装，开始安装..."
    curl -fsSL https://get.docker.com | sh
    systemctl start docker
    systemctl enable docker
    echo "  ✅ Docker 安装完成"
else
    echo "  ✅ Docker 已安装: $(docker --version)"
fi

if ! docker compose version &>/dev/null; then
    echo "  ❌ Docker Compose 不可用，请手动安装"
    exit 1
fi

# ---- 2. 配置 Docker 镜像源（国内加速）----
echo ""
echo "🪞 [2/6] 配置 Docker 镜像源..."
DAEMON_JSON="/etc/docker/daemon.json"
if [ ! -f "$DAEMON_JSON" ] || ! grep -q "registry-mirrors" "$DAEMON_JSON" 2>/dev/null; then
    cat > "$DAEMON_JSON" << 'MIRRORS'
{
  "registry-mirrors": [
    "https://docker.1ms.run",
    "https://docker.xuanyuan.me",
    "https://docker.m.daocloud.io"
  ]
}
MIRRORS
    systemctl restart docker
    echo "  ✅ 镜像源已配置"
else
    echo "  ✅ 镜像源已存在，跳过"
fi

# ---- 3. 创建 Swap（如果不存在）----
echo ""
echo "💾 [3/6] 检查 Swap..."
if [ "$(swapon --show | wc -l)" -le 1 ]; then
    echo "  创建 8G swap..."
    fallocate -l 8G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    if ! grep -q "/swapfile" /etc/fstab; then
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
    fi
    echo "  ✅ Swap 已创建"
else
    echo "  ✅ Swap 已存在: $(free -h | grep Swap | awk '{print $2}')"
fi

# ---- 4. 部署 Gemini Business2API ----
echo ""
echo "🐳 [4/6] 部署 Gemini Business2API..."
mkdir -p "$DEPLOY_DIR"

# 复制配置文件
cp "$SCRIPT_DIR/docker-compose.yml" "$DEPLOY_DIR/docker-compose.yml"

# 如果 .env 不存在，从模板创建
if [ ! -f "$DEPLOY_DIR/.env" ]; then
    if [ -f "$SCRIPT_DIR/.env.example" ]; then
        cp "$SCRIPT_DIR/.env.example" "$DEPLOY_DIR/.env"
        # 生成随机 ADMIN_KEY
        RANDOM_KEY=$(openssl rand -base64 24)
        sed -i "s|your-secure-admin-key-here|$RANDOM_KEY|" "$DEPLOY_DIR/.env"
        echo "  ⚠️  已生成随机 ADMIN_KEY: $RANDOM_KEY"
        echo "  ⚠️  请记住此密钥，用于登录管理面板"
    fi
else
    echo "  .env 已存在，保留现有配置"
fi

cd "$DEPLOY_DIR"
docker compose pull
docker compose up -d
echo "  ✅ 容器已启动"

# ---- 5. 配置 Clash 代理规则 ----
echo ""
echo "🌐 [5/6] 检查 Clash 代理规则..."
CLASH_CONFIG="$CLASH_DIR/config.yaml"
if [ -f "$CLASH_CONFIG" ]; then
    # 检查是否有 .google 顶级域规则
    if ! grep -q "DOMAIN-SUFFIX,google,Proxy" "$CLASH_CONFIG"; then
        # 在 google.com 规则前插入 .google 规则
        sed -i '/DOMAIN-SUFFIX,google\.com,Proxy/i\  - DOMAIN-SUFFIX,google,Proxy' "$CLASH_CONFIG"
        echo "  ✅ 已添加 .google 顶级域代理规则"
        # 重载 clash
        if pgrep mihomo &>/dev/null; then
            kill -HUP $(pgrep mihomo)
            echo "  ✅ Clash 已重载"
        fi
    else
        echo "  ✅ .google 规则已存在"
    fi
else
    echo "  ⚠️  未找到 Clash 配置，跳过"
    echo "  ⚠️  请确保代理能访问 *.google 和 *.google.com"
fi

# ---- 6. 等待健康检查 ----
echo ""
echo "🏥 [6/6] 等待服务就绪..."
for i in $(seq 1 30); do
    if curl -sf http://localhost:7860/admin/health &>/dev/null; then
        echo "  ✅ 服务健康检查通过"
        break
    fi
    if [ "$i" -eq 30 ]; then
        echo "  ❌ 健康检查超时，请检查日志: docker compose -f $DEPLOY_DIR/docker-compose.yml logs"
        exit 1
    fi
    sleep 2
done

# ---- 完成 ----
echo ""
echo "================================"
echo "🎉 部署完成！"
echo ""
echo "📋 信息："
echo "  管理面板: http://$(hostname -I | awk '{print $1}'):7860"
echo "  API 端点: http://localhost:7860/v1/chat/completions"
echo "  健康检查: http://localhost:7860/admin/health"
echo ""
echo "📝 首次使用："
echo "  1. 打开管理面板，用 ADMIN_KEY 登录"
echo "  2. 系统设置中配置："
echo "     - proxy_for_auth: http://host.docker.internal:7890"
echo "     - proxy_for_chat: http://host.docker.internal:7890"
echo "     - 邮箱域名: duckmail.sbs"
echo "     - 关闭 headless 模式"
echo "  3. 账户管理中点击「自动注册」"
echo ""
echo "⚠️  注意事项："
echo "  - 不要在 .env 中设置 HTTP_PROXY（会干扰浏览器自动化）"
echo "  - 代理必须支持 .google 顶级域（不只是 .google.com）"
echo "  - Cookie 约 12 小时过期，需定期重新注册"
echo "  - 容器重启请用 docker compose down && docker compose up -d"
echo "    不要用 docker compose restart（Xvfb 不会重启）"
