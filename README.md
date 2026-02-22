# Gemini Business2API 部署

一键部署 [Gemini Business2API](https://github.com/cooooookk/gemini-business2api) 到 Linux 服务器（OpenCloudOS / CentOS / RHEL 系列）。

## 快速开始

```bash
git clone https://github.com/YOUR_USERNAME/gemini-business2api-deploy.git
cd gemini-business2api-deploy
chmod +x deploy.sh setup.sh
./deploy.sh
./setup.sh
```

## 文件说明

| 文件 | 说明 |
|------|------|
| `deploy.sh` | 一键部署：安装 Docker、配置镜像源、创建 Swap、启动容器、修复 Clash 规则 |
| `setup.sh` | 自动配置管理面板：设置代理、邮箱、headless 等 |
| `docker-compose.yml` | Docker Compose 配置 |
| `.env.example` | 环境变量模板 |

## 部署流程

1. `deploy.sh` — 安装依赖、启动容器
2. `setup.sh [代理地址]` — 自动配置管理面板（默认代理 `http://host.docker.internal:7890`）
3. 打开管理面板 `http://服务器IP:7860`，点击「自动注册」创建 Google 账户

## 踩坑记录

### 1. 不要在 .env 设置全局代理

```bash
# ❌ 错误：会干扰 Chromium DevTools WebSocket 连接
HTTP_PROXY=http://host.docker.internal:7890
HTTPS_PROXY=http://host.docker.internal:7890

# ✅ 正确：通过管理面板设置 proxy_for_auth 和 proxy_for_chat
```

全局 `HTTP_PROXY` 会导致 DrissionPage 连接 Chromium 的 WebSocket 也走代理，连接失败报 "Connection to remote host was lost"。

### 2. Clash 规则必须包含 .google 顶级域

```yaml
rules:
  - DOMAIN-SUFFIX,google,Proxy      # ← 必须！.google 顶级域
  - DOMAIN-SUFFIX,google.com,Proxy  # 这个不够
```

`auth.business.gemini.google` 是 `.google` 顶级域，不是 `.google.com`。缺少这条规则会导致 TLS 握手失败。

### 3. 容器重启必须用 down + up

```bash
# ❌ 错误：restart 不会重跑 entrypoint，Xvfb 不会启动
docker compose restart

# ✅ 正确：完整重建，entrypoint 会启动 Xvfb
docker compose down && docker compose up -d
```

### 4. proxy_for_chat 必须设置

管理面板有两个代理设置：
- `proxy_for_auth` — 浏览器自动化用（注册/登录 Google）
- `proxy_for_chat` — API 调用 Google 用

两个都要设，否则 API 调用会走直连被墙。

### 5. 可用模型

gemini-2.0-flash 已下线，当前可用：
- `gemini-2.5-flash` / `gemini-2.5-pro`
- `gemini-3-flash-preview` / `gemini-3-pro-preview`
- `gemini-auto`（自动选择）

## Cookie 有效期

Google 会话 Cookie 约 12 小时过期，需要定期重新注册。可通过管理面板手动操作或配置自动续期。

## 服务器要求

- 内存 ≥ 2GB（推荐 4GB+），建议配置 Swap
- 需要能访问 Google 的代理（支持 `.google` 顶级域）
- Docker + Docker Compose
