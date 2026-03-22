#!/bin/bash
# =============================================================================
#  🦞 OpenClaw 自媒體班 — 全自動安裝腳本
#  cloud-init user-data 版（貼到建立 VM 時的 User data 欄位）
#
#  Repos:
#    主程式安裝腳本（Public）: Joanna8521/openclaw-install_media
#    技能庫（Private）:        Joanna8521/openclaw_media
#
#  ★ 安裝前請先把下面五個欄位換成你自己的值 ★
# =============================================================================

# ── 請填入你的設定（只需改這五行）────────────────────────────────────────────
LINE_TOKEN="請把這裡換成你的LINE_Channel_Access_Token"
TG_TOKEN=""                  # Telegram Bot Token（選填，有的話填進來）
AI_KEY="請把這裡換成你的Claude_或Gemini_API_Key"
AI_ENGINE="claude"           # claude 或 gemini 二選一
NGROK_TOKEN="請把這裡換成你的ngrok_Auth_Token"
NGROK_DOMAIN="請把這裡換成你的ngrok靜態網域"  # 例如：profound-frank-kangaroo.ngrok-free.app
SKILLS_PAT="請把這裡換成老師給的Skills存取碼"
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail
exec > /var/log/openclaw-install.log 2>&1

INSTALL_DIR="/opt/openclaw"
SKILLS_DIR="/root/.openclaw/skills"

# ── 1. 系統套件 ────────────────────────────────────────────────────────────────
apt-get update -qq
apt-get install -y -qq git curl wget jq nginx unzip 2>/dev/null

# ── 2. Node.js 22 ──────────────────────────────────────────────────────────────
curl -fsSL https://deb.nodesource.com/setup_22.x | bash - 2>/dev/null
apt-get install -y -qq nodejs
npm install -g pnpm --quiet 2>/dev/null

# ── 3. ngrok（x86_64，歐洲 Hetzner CX22）─────────────────────────────────────
wget -q -O /tmp/ngrok.zip \
  "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-amd64.zip"
unzip -q /tmp/ngrok.zip -d /tmp/
mv /tmp/ngrok /usr/local/bin/ngrok
chmod +x /usr/local/bin/ngrok
ngrok config add-authtoken "$NGROK_TOKEN" 2>/dev/null || true

# 取得 ngrok 靜態網域（免費帳號分配的固定網址）
NGROK_DOMAIN=$(ngrok api tunnels list \
  --api-key "$NGROK_TOKEN" 2>/dev/null | jq -r '.tunnels[0].public_url' 2>/dev/null || echo "")

# 建立 ngrok systemd 服務
cat > /etc/systemd/system/ngrok.service << 'NGROK_SVC'
[Unit]
Description=ngrok HTTPS Tunnel
After=network.target openclaw.service

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/ngrok http --log=stdout 18789
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
NGROK_SVC

# ── 4. OpenClaw 主程式 ─────────────────────────────────────────────────────────
rm -rf "$INSTALL_DIR"
git clone --depth 1 --quiet \
  "https://github.com/openclaw/openclaw.git" "$INSTALL_DIR" 2>/dev/null

cd "$INSTALL_DIR"
pnpm install --silent 2>/dev/null || true
pnpm run build --silent 2>/dev/null || true

# 初始化設定
node "$INSTALL_DIR/openclaw.mjs" setup 2>/dev/null || true
node "$INSTALL_DIR/openclaw.mjs" config set gateway.mode local 2>/dev/null || true
node "$INSTALL_DIR/openclaw.mjs" config set gateway.port 18789 2>/dev/null || true
node "$INSTALL_DIR/openclaw.mjs" config set skills.load.extraDirs '["/root/.openclaw/skills"]' 2>/dev/null || true

# LINE 設定
node "$INSTALL_DIR/openclaw.mjs" config set channels.line.enabled true 2>/dev/null || true
node "$INSTALL_DIR/openclaw.mjs" config set channels.line.channelAccessToken "$LINE_TOKEN" 2>/dev/null || true

# Telegram 設定（選填）
if [ -n "$TG_TOKEN" ]; then
  node "$INSTALL_DIR/openclaw.mjs" config set channels.telegram.enabled true 2>/dev/null || true
  node "$INSTALL_DIR/openclaw.mjs" config set channels.telegram.botToken "$TG_TOKEN" 2>/dev/null || true
  node "$INSTALL_DIR/openclaw.mjs" config set channels.telegram.dmPolicy pairing 2>/dev/null || true
fi

# AI 引擎設定（寫入 .env，openclaw 自動載入）
OPENCLAW_ENV_FILE="/root/.openclaw/.env"
mkdir -p /root/.openclaw
case "$AI_ENGINE" in
  gemini)
    AI_MODEL="google/gemini-2.5-pro"
    echo "GOOGLE_API_KEY=${AI_KEY}" > "$OPENCLAW_ENV_FILE"
    ;;
  *)
    AI_MODEL="anthropic/claude-sonnet-4-6"
    echo "ANTHROPIC_API_KEY=${AI_KEY}" > "$OPENCLAW_ENV_FILE"
    ;;
esac
chmod 600 "$OPENCLAW_ENV_FILE"
node "$INSTALL_DIR/openclaw.mjs" config set agents.defaults.model.primary "$AI_MODEL" 2>/dev/null || true

# Anthropic 還需要 paste-token
if [ "$AI_ENGINE" != "gemini" ] && [ -n "$AI_KEY" ]; then
  echo "$AI_KEY" | node "$INSTALL_DIR/openclaw.mjs" models auth paste-token \
    --provider anthropic 2>/dev/null || true
fi

# ── 5. Skills 安裝 ─────────────────────────────────────────────────────────────
mkdir -p "$SKILLS_DIR"
if [[ -n "$SKILLS_PAT" && "$SKILLS_PAT" != 請把* ]]; then
  TMP_SKILLS="/tmp/skills_repo"

  # 方法一：git clone（repo 有 skills/ 結構時）
  if git clone --depth 1 --quiet \
    "https://${SKILLS_PAT}@github.com/Joanna8521/openclaw_media.git" \
    "$TMP_SKILLS" 2>/dev/null; then

    if [[ -d "$TMP_SKILLS/skills" ]]; then
      # 正常結構：skills/ 資料夾在裡面
      cp -r "$TMP_SKILLS/skills/"* "$SKILLS_DIR/" 2>/dev/null || true
    else
      # 備案：skills 直接在 repo 根目錄
      find "$TMP_SKILLS" -name "SKILL.md" | while read f; do
        skill_dir=$(dirname "$f")
        folder_name=$(basename "$skill_dir")
        mkdir -p "$SKILLS_DIR/$folder_name"
        cp "$f" "$SKILLS_DIR/$folder_name/SKILL.md"
      done
    fi
    rm -rf "$TMP_SKILLS"

  # 方法二：下載 zip（GitHub Release 或手動上傳的 zip）
  elif curl -sfL \
    -H "Authorization: token ${SKILLS_PAT}" \
    "https://api.github.com/repos/Joanna8521/openclaw_media/zipball/main" \
    -o /tmp/skills.zip 2>/dev/null; then

    mkdir -p /tmp/skills_unzip
    unzip -q /tmp/skills.zip -d /tmp/skills_unzip 2>/dev/null || true
    # 找 SKILL.md 不管在哪層
    find /tmp/skills_unzip -name "SKILL.md" | while read f; do
      skill_dir=$(dirname "$f")
      folder_name=$(basename "$skill_dir")
      if [[ "$folder_name" != "skills_unzip" && "$folder_name" != "." ]]; then
        mkdir -p "$SKILLS_DIR/$folder_name"
        cp "$f" "$SKILLS_DIR/$folder_name/SKILL.md"
      fi
    done
    rm -rf /tmp/skills_unzip /tmp/skills.zip
  fi
fi

# ── 6. Nginx ────────────────────────────────────────────────────────────────────
cat > /etc/nginx/sites-available/openclaw << 'NGINX_CONF'
server {
    listen 80;
    server_name _;
    location /line/webhook {
        proxy_pass http://127.0.0.1:18789/line/webhook;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_read_timeout 60s;
    }
    location /health {
        proxy_pass http://127.0.0.1:18789/health;
    }
    location / {
        return 200 '🦞 OpenClaw running';
        add_header Content-Type text/plain;
    }
}
NGINX_CONF
ln -sf /etc/nginx/sites-available/openclaw /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
nginx -t -q && systemctl reload nginx 2>/dev/null || true

# ── 7. systemd 服務 ────────────────────────────────────────────────────────────
cat > /etc/systemd/system/openclaw.service << OPENCLAW_SVC
[Unit]
Description=OpenClaw 自媒體班龍蝦助理
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=${INSTALL_DIR}
ExecStart=node ${INSTALL_DIR}/openclaw.mjs gateway
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
OPENCLAW_SVC

systemctl daemon-reload
systemctl enable openclaw ngrok
systemctl start openclaw
sleep 8
systemctl start ngrok
sleep 5

# ── 8. 取得 ngrok HTTPS 網址 ───────────────────────────────────────────────────
# 等 ngrok 啟動後從 API 取得公開 URL
for i in {1..10}; do
  NGROK_URL=$(curl -s http://localhost:4040/api/tunnels 2>/dev/null \
    | python3 -c "import sys,json; t=json.load(sys.stdin).get('tunnels',[]); print(t[0]['public_url'] if t else '')" 2>/dev/null || echo "")
  [[ -n "$NGROK_URL" ]] && break
  sleep 3
done

PUBLIC_IP=$(curl -s --max-time 5 ifconfig.me 2>/dev/null || echo "")
SKILL_COUNT=$(find "$SKILLS_DIR" -name "SKILL.md" 2>/dev/null | wc -l)

# ── 9. 用 LINE 推播完成通知 ────────────────────────────────────────────────────
WEBHOOK_URL="${NGROK_URL}/line/webhook"
SERVICE_STATUS=$(systemctl is-active openclaw 2>/dev/null || echo "unknown")

TG_MSG=""
if [ -n "$TG_TOKEN" ]; then
  TG_MSG="
Telegram Bot：
傳訊息給 Bot → 收到配對碼
貼給 VM：
sudo node /opt/openclaw/openclaw.mjs pairing approve telegram 配對碼"
fi

LINE_MSG="🦞 OpenClaw 安裝完成！

服務狀態：${SERVICE_STATUS}
已安裝 Skill：${SKILL_COUNT} 個
VM IP：${PUBLIC_IP}

LINE Webhook 設定：
1. LINE Developers Console
2. Messaging API → Webhook URL
3. 填入：${WEBHOOK_URL}
4. Verify → 開啟 Use webhook
5. 關閉 Auto-reply messages
${TG_MSG}
⚠️ ngrok 靜態網址需到 ngrok.com → Domains 確認固定網域"

curl -s -X POST "https://api.line.me/v2/bot/message/broadcast" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${LINE_TOKEN}" \
  -d "{\"messages\":[{\"type\":\"text\",\"text\":\"${LINE_MSG}\"}]}" \
  2>/dev/null || true

echo "=== OpenClaw 安裝完成 ===" >> /var/log/openclaw-install.log
echo "Skills: ${SKILL_COUNT}" >> /var/log/openclaw-install.log
echo "Webhook URL: ${WEBHOOK_URL}" >> /var/log/openclaw-install.log
