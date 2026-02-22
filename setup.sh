#!/bin/bash
set -e

# ============================================================
# Gemini Business2API 管理面板自动配置脚本
# 在 deploy.sh 之后运行，自动配置管理面板设置
# ============================================================

API_URL="http://localhost:7860"
COOKIE_FILE="/tmp/gemini-setup-cookies.txt"

# 读取 ADMIN_KEY
DEPLOY_DIR="/opt/gemini-business2api"
ADMIN_KEY=$(grep "^ADMIN_KEY=" "$DEPLOY_DIR/.env" | cut -d= -f2-)

if [ -z "$ADMIN_KEY" ]; then
    echo "❌ 未找到 ADMIN_KEY，请检查 $DEPLOY_DIR/.env"
    exit 1
fi

# 代理地址（可通过参数覆盖）
PROXY_ADDR="${1:-http://host.docker.internal:7890}"

echo "🔧 Gemini Business2API 自动配置"
echo "================================"
echo "  代理地址: $PROXY_ADDR"
echo ""

# ---- 1. 登录 ----
echo "🔑 [1/3] 登录管理面板..."
LOGIN_RESULT=$(curl -s -c "$COOKIE_FILE" "$API_URL/login" \
    -X POST \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "admin_key=$ADMIN_KEY")

if echo "$LOGIN_RESULT" | grep -q '"success":true'; then
    echo "  ✅ 登录成功"
else
    echo "  ❌ 登录失败: $LOGIN_RESULT"
    exit 1
fi

# ---- 2. 配置系统设置 ----
echo ""
echo "⚙️  [2/3] 配置系统设置..."

# 设置 proxy_for_auth 和 proxy_for_chat
SETTINGS_RESULT=$(curl -s -b "$COOKIE_FILE" "$API_URL/admin/settings" \
    -X PUT \
    -H "Content-Type: application/json" \
    -d "{\"basic\":{\"proxy_for_auth\":\"$PROXY_ADDR\",\"proxy_for_chat\":\"$PROXY_ADDR\",\"browser_headless\":false,\"register_domain\":\"duckmail.sbs\",\"temp_mail_provider\":\"duckmail\"}}")

if echo "$SETTINGS_RESULT" | grep -q '"success"'; then
    echo "  ✅ 设置已保存"
else
    echo "  ❌ 设置失败: $SETTINGS_RESULT"
    exit 1
fi

# ---- 3. 验证 ----
echo ""
echo "✅ [3/3] 验证配置..."
SETTINGS=$(curl -s -b "$COOKIE_FILE" "$API_URL/admin/settings")
echo "$SETTINGS" | python3 -c "
import json,sys
d=json.load(sys.stdin)['basic']
print(f\"  proxy_for_auth: {d['proxy_for_auth']}\")
print(f\"  proxy_for_chat: {d['proxy_for_chat']}\")
print(f\"  headless: {d['browser_headless']}\")
print(f\"  mail_provider: {d['temp_mail_provider']}\")
print(f\"  domain: {d['register_domain']}\")
"

# 清理
rm -f "$COOKIE_FILE"

echo ""
echo "================================"
echo "🎉 配置完成！"
echo ""
echo "下一步：打开管理面板，在「账户管理」中点击「自动注册」"
echo "  管理面板: $API_URL"
