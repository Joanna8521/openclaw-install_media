#!/bin/bash
# =============================================================================
#  🦞  OpenClaw Bootstrap 安裝腳本
#      自媒體班 × OpenClaw_media 課程
#
#  ⚠️  不可用 curl | bash 執行！請先下載再跑：
#    curl -fsSL https://raw.githubusercontent.com/Joanna8521/openclaw-install_media/main/bootstrap.sh -o bootstrap.sh && chmod +x bootstrap.sh && sudo ./bootstrap.sh
#
#  自動完成：
#    1. 系統套件更新 + Node.js v22 安裝
#    2. 從 GitHub 安裝 OpenClaw 主程式
#    3. 安裝自媒體班 Skills（Joanna8521/openclaw_media）
#    4. 設定 Nginx 反向代理（Port 80）
#    5. 設定 systemd 服務（開機自動啟動）
#    6. 互動式設定 AI 引擎 + Bot Token
#
#  已驗證環境：Ubuntu 22.04 ARM（Oracle VM.Standard.A1.Flex）
#  需要 Node.js v22+（腳本自動安裝）
# =============================================================================
set -euo pipefail

# ── 顏色 ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

print_ok()   { echo -e "  ${GREEN}✅ ${RESET} $1"; }
print_info() { echo -e "  ${CYAN}⚙️ ${RESET}  $1"; }
print_warn() { echo -e "  ${YELLOW}⚠️ ${RESET}  $1"; }
print_err()  { echo -e "  ${RED}❌${RESET}  $1"; }
section()    { echo -e "\n${BLUE}════════════════════════════════════════════${RESET}"; echo -e "  ${BOLD}$1${RESET}"; echo -e "${BLUE}════════════════════════════════════════════${RESET}"; }

# ── 必須是 root ──────────────────────────────────────────────────────────────
if [ "$EUID" -ne 0 ]; then
  print_err "請用 sudo 執行：sudo bash bootstrap.sh"
  exit 1
fi

# ── 變數 ────────────────────────────────────────────────────────────────────
INSTALL_DIR="/opt/openclaw"
SKILLS_DIR="/root/.openclaw/skills"
OPENCLAW_REPO="https://github.com/openclaw/openclaw.git"
SERVICE_FILE="/etc/systemd/system/openclaw.service"
NGINX_CONF="/etc/nginx/sites-available/openclaw"

# ── Banner ──────────────────────────────────────────────────────────────────
clear
echo -e "${BOLD}"
cat << 'BANNER'
  ╔═══════════════════════════════════════════╗
  ║                                           ║
  ║     🦞  OpenClaw 安裝腳本                 ║
  ║         自媒體班 × OpenClaw_media 課程    ║
  ║                                           ║
  ╚═══════════════════════════════════════════╝
BANNER
echo -e "${RESET}"

# ── STEP 1：收集設定資訊 ──────────────────────────────────────────────────────
section "STEP 1｜設定資訊輸入"

echo ""
echo "  請依序輸入以下設定。輸入密碼/Key 時畫面不顯示字，這是正常安全機制。"
echo ""

# ── AI 引擎選擇 ──────────────────────────────────────────────────────────────
echo "  選擇 AI 引擎："
echo "  1) Claude（Anthropic）  — 推薦，繁中支援最好"
echo "  2) Gemini（Google）     — 免費額度較多"
echo ""
read -r -p "  請輸入選項 [1/2，預設 1]：" AI_CHOICE
echo ""

case "${AI_CHOICE:-1}" in
  2)
    AI_PROVIDER="google"
    AI_MODEL="google/gemini-2.5-pro"
    AI_ENV_VAR="GOOGLE_API_KEY"
    AI_LABEL="Gemini API Key（aistudio.google.com 取得）"
    AI_EXTRA_CONFIG=""
    ;;
  *)
    AI_PROVIDER="anthropic"
    AI_MODEL="anthropic/claude-sonnet-4-6"
    AI_ENV_VAR="ANTHROPIC_API_KEY"
    AI_LABEL="Claude API Key（console.anthropic.com 取得）"
    AI_EXTRA_CONFIG=""
    ;;
esac

read -r -s -p "  請貼上 ${AI_LABEL}：" AI_KEY
echo ""
if [ -z "$AI_KEY" ]; then
  print_warn "未輸入 API Key，稍後可手動設定"
fi

# ── Telegram Bot Token（主要頻道） ────────────────────────────────────────────
echo ""
echo "  ── Telegram Bot Token（主要通知頻道）──────────"
echo "  取得方式：Telegram 搜尋 @BotFather → /newbot → 取得 Token"
echo ""
read -r -s -p "  請貼上 Telegram Bot Token：" TG_TOKEN
echo ""
if [ -z "$TG_TOKEN" ]; then
  print_warn "未輸入 Telegram Token，稍後可手動設定"
fi

# ── LINE Bot Token（可選） ────────────────────────────────────────────────────
echo ""
echo "  ── LINE Bot（選填，可略過）────────────────────"
read -r -p "  要設定 LINE Bot 嗎？[y/N]：" SETUP_LINE
if [[ "${SETUP_LINE,,}" == "y" ]]; then
  read -r -s -p "  LINE Channel Secret：" LINE_SECRET
  echo ""
  read -r -s -p "  LINE Channel Access Token：" LINE_TOKEN
  echo ""
else
  LINE_SECRET=""
  LINE_TOKEN=""
fi

# ── Skills PAT ────────────────────────────────────────────────────────────────
echo ""
echo "  ── 課程技能庫存取碼 ───────────────────────────"
PAT_FILE="/root/.openclaw/skills_pat"
if [ -f "$PAT_FILE" ]; then
  SKILLS_PAT=$(cat "$PAT_FILE")
  print_ok "課程存取碼已從設定檔讀取"
else
  read -r -s -p "  請貼上課程存取碼（github_pat_...）：" SKILLS_PAT
  echo ""
fi

# ── 確認資訊 ─────────────────────────────────────────────────────────────────
echo ""
echo "  ── 確認設定 ─────────────────────────────────────"
echo "  AI 引擎：${AI_PROVIDER} / ${AI_MODEL}"
[ -n "$AI_KEY" ]    && echo "  API Key：✅ 已設定" || echo "  API Key：⚠️  未設定"
[ -n "$TG_TOKEN" ]  && echo "  Telegram：✅ 已設定" || echo "  Telegram：⚠️  未設定"
[ -n "$LINE_TOKEN" ] && echo "  LINE：✅ 已設定" || echo "  LINE：略過"
[ -n "$SKILLS_PAT" ] && echo "  Skills PAT：✅ 已設定" || echo "  Skills PAT：⚠️  未設定"
echo ""
read -r -p "  確認無誤？按 Enter 開始安裝（Ctrl+C 中止）..."

# ── STEP 2：系統更新 + 套件 ──────────────────────────────────────────────────
section "STEP 2｜系統更新與套件安裝"
print_info "更新 apt 套件清單..."
apt-get update -qq

print_info "安裝基礎套件..."
apt-get install -y -qq \
  git curl wget jq nginx cron build-essential \
  ca-certificates gnupg lsb-release unzip 2>/dev/null
print_ok "基礎套件安裝完成"

# ── STEP 3：Node.js v22 ──────────────────────────────────────────────────────
section "STEP 3｜Node.js v22 安裝"
NODE_VER=$(node --version 2>/dev/null || echo "none")
NODE_MAJOR=$(echo "$NODE_VER" | grep -oP '(?<=v)\d+' || echo "0")

if [ "${NODE_MAJOR:-0}" -lt 22 ]; then
  print_info "目前 Node.js $NODE_VER，升級到 v22..."
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash - 2>/dev/null
  apt-get install -y -qq nodejs
  print_ok "Node.js $(node --version) 安裝完成"
else
  print_ok "Node.js $NODE_VER 已符合需求（>= v22）"
fi

# ── STEP 4：OpenClaw 主程式 ──────────────────────────────────────────────────
section "STEP 4｜OpenClaw 主程式安裝"
if [ -d "$INSTALL_DIR/.git" ]; then
  print_info "OpenClaw 已存在，更新到最新版..."
  cd "$INSTALL_DIR" && git pull --quiet
else
  print_info "從 GitHub 下載 OpenClaw..."
  rm -rf "$INSTALL_DIR"
  git clone --depth 1 --quiet "$OPENCLAW_REPO" "$INSTALL_DIR"
fi
print_ok "OpenClaw 主程式下載完成"

print_info "安裝 pnpm..."
npm install -g pnpm --quiet 2>/dev/null
print_ok "pnpm 安裝完成"

print_info "安裝套件依賴..."
cd "$INSTALL_DIR"
pnpm install --silent 2>/dev/null
print_ok "套件依賴安裝完成"

print_info "Build OpenClaw..."
pnpm run build --silent 2>/dev/null || true
print_ok "Build 完成"

# ── STEP 5：初始化 OpenClaw 設定 ─────────────────────────────────────────────
section "STEP 5｜初始化 OpenClaw 設定"

print_info "初始化設定檔..."
node "$INSTALL_DIR/openclaw.mjs" setup 2>/dev/null || true
node "$INSTALL_DIR/openclaw.mjs" config set gateway.mode local 2>/dev/null || true
node "$INSTALL_DIR/openclaw.mjs" config set gateway.port 18789 2>/dev/null || true

# Skills 目錄（自媒體班 flat 結構）
node "$INSTALL_DIR/openclaw.mjs" config set skills.load.extraDirs '["/root/.openclaw/skills"]' 2>/dev/null || true

# ── AI 引擎設定（環境變數 + paste-token 雙保險）────────────────────────────
if [ -n "$AI_KEY" ]; then
  # 1. 寫入 ~/.openclaw/.env（openclaw 自動載入）
  OPENCLAW_ENV_FILE="/root/.openclaw/.env"
  touch "$OPENCLAW_ENV_FILE"
  # 移除舊的同名 key，再追加新的
  grep -v "^${AI_ENV_VAR}=" "$OPENCLAW_ENV_FILE" > "${OPENCLAW_ENV_FILE}.tmp" 2>/dev/null || true
  echo "${AI_ENV_VAR}=${AI_KEY}" >> "${OPENCLAW_ENV_FILE}.tmp"
  mv "${OPENCLAW_ENV_FILE}.tmp" "$OPENCLAW_ENV_FILE"
  chmod 600 "$OPENCLAW_ENV_FILE"

  # 2. 設定 model
  node "$INSTALL_DIR/openclaw.mjs" config set agents.defaults.model.primary "$AI_MODEL" 2>/dev/null || true

  # 3. Anthropic 還需要 paste-token（其他 provider 靠環境變數就夠）
  if [ "$AI_PROVIDER" = "anthropic" ]; then
    echo "$AI_KEY" | node "$INSTALL_DIR/openclaw.mjs" models auth paste-token \
      --provider anthropic 2>/dev/null || true
  fi

  # 4. DeepSeek / MiniMax / Kimi 需要寫 custom provider 設定
  if [ -n "$AI_EXTRA_CONFIG" ]; then
    # 把 custom provider 的 env var 也寫入 .env
    # AI_EXTRA_CONFIG 只用來記錄需要 custom provider，實際設定靠 .env
    print_info "Custom provider（${AI_PROVIDER}）設定完成（透過環境變數）"
  fi

  print_ok "AI 引擎設定完成（${AI_PROVIDER} / ${AI_MODEL}）"
else
  print_warn "API Key 未設定，稍後手動執行："
  print_warn "  Anthropic: sudo node $INSTALL_DIR/openclaw.mjs models auth paste-token --provider anthropic"
  print_warn "  其他:      echo 'API_KEY_VAR=你的Key' >> /root/.openclaw/.env"
fi

# ── Telegram 設定 ────────────────────────────────────────────────────────────
if [ -n "$TG_TOKEN" ]; then
  node "$INSTALL_DIR/openclaw.mjs" config set channels.telegram.enabled true 2>/dev/null || true
  node "$INSTALL_DIR/openclaw.mjs" config set channels.telegram.botToken "$TG_TOKEN" 2>/dev/null || true
  node "$INSTALL_DIR/openclaw.mjs" config set channels.telegram.dmPolicy pairing 2>/dev/null || true
  print_ok "Telegram Bot Token 設定完成"
fi

# ── LINE 設定 ────────────────────────────────────────────────────────────────
if [ -n "$LINE_TOKEN" ] && [ -n "$LINE_SECRET" ]; then
  node "$INSTALL_DIR/openclaw.mjs" config set channels.line.enabled true 2>/dev/null || true
  node "$INSTALL_DIR/openclaw.mjs" config set channels.line.channelSecret "$LINE_SECRET" 2>/dev/null || true
  node "$INSTALL_DIR/openclaw.mjs" config set channels.line.accessToken "$LINE_TOKEN" 2>/dev/null || true
  print_ok "LINE Bot 設定完成"
fi

print_ok "OpenClaw 設定初始化完成"

# ── STEP 6：安裝自媒體班 Skills ──────────────────────────────────────────────
section "STEP 6｜安裝自媒體班 Skills（C01–C10 + D01 + S01–S141）"
mkdir -p "$SKILLS_DIR"

if [ -z "$SKILLS_PAT" ]; then
  print_warn "未提供課程存取碼，跳過 Skills 安裝"
  print_warn "之後可手動執行：git clone https://<存取碼>@github.com/Joanna8521/openclaw_media.git /tmp/skills_tmp && cp -r /tmp/skills_tmp/skills/* /root/.openclaw/skills/"
else
  print_info "從 GitHub 下載自媒體班 Skills..."
  TMP_SKILLS="/tmp/openclaw_media_skills_install"
  rm -rf "$TMP_SKILLS"
  CLONE_URL="https://${SKILLS_PAT}@github.com/Joanna8521/openclaw_media.git"

  if git clone --depth 1 --quiet "$CLONE_URL" "$TMP_SKILLS" 2>/dev/null; then
    if [ -d "$TMP_SKILLS/skills" ]; then
      cp -r "$TMP_SKILLS/skills/"* "$SKILLS_DIR/" 2>/dev/null || true
      SKILL_COUNT=$(find "$SKILLS_DIR" -name 'SKILL.md' | wc -l)
      print_ok "自媒體班 Skills 安裝完成（${SKILL_COUNT} 個技能）"
    else
      print_warn "Skills 目錄結構不符預期，請確認 repo 內有 skills/ 資料夾"
    fi
    rm -rf "$TMP_SKILLS"
  else
    print_err "存取碼錯誤或 repo 不存在，Skills 安裝失敗"
    print_warn "請確認存取碼後重新執行此腳本"
  fi
fi

# ── STEP 7：Nginx 設定 ───────────────────────────────────────────────────────
section "STEP 7｜設定 Nginx 反向代理"
cat > "$NGINX_CONF" << 'NGINX'
server {
    listen 80;
    server_name _;

    location /line/webhook {
        proxy_pass http://127.0.0.1:18789/line/webhook;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_read_timeout 60s;
    }

    location /telegram/webhook {
        proxy_pass http://127.0.0.1:18789/telegram/webhook;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_read_timeout 60s;
    }

    location /health {
        proxy_pass http://127.0.0.1:18789/health;
        proxy_http_version 1.1;
    }

    location /api/ {
        proxy_pass http://127.0.0.1:18789/api/;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
NGINX

ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/openclaw
rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true
nginx -t -q 2>/dev/null && systemctl reload nginx && print_ok "Nginx 設定完成" \
  || print_warn "Nginx 設定有問題，請執行 nginx -t 查看詳情"

# ── STEP 8：systemd 服務 ─────────────────────────────────────────────────────
section "STEP 8｜設定 systemd 自動啟動服務"
cat > "$SERVICE_FILE" << SYSTEMD
[Unit]
Description=OpenClaw AI 龍蝦助理（自媒體班）
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=${INSTALL_DIR}
ExecStart=/usr/bin/node ${INSTALL_DIR}/openclaw.mjs gateway
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
SYSTEMD

systemctl daemon-reload
systemctl enable openclaw --quiet
systemctl restart openclaw
sleep 5

if systemctl is-active --quiet openclaw; then
  print_ok "systemd 服務啟動完成"
else
  print_warn "服務啟動失敗，查看 log："
  journalctl -u openclaw -n 15 --no-pager
fi

# ── STEP 9：健康檢查 ─────────────────────────────────────────────────────────
section "STEP 9｜健康檢查"
PUBLIC_IP=$(curl -s --max-time 5 http://checkip.amazonaws.com 2>/dev/null \
  || curl -s --max-time 5 ifconfig.me 2>/dev/null \
  || echo "無法取得")
SKILL_COUNT_FINAL=$(find "$SKILLS_DIR" -name "SKILL.md" 2>/dev/null | wc -l)

HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:18789/health 2>/dev/null || echo "000")

print_ok "VM Public IP：$PUBLIC_IP"
print_ok "已安裝 Skill 數量：${SKILL_COUNT_FINAL} / 152"
[ "$HTTP_STATUS" = "200" ] && print_ok "Gateway 回應正常（HTTP $HTTP_STATUS）" \
  || print_warn "Gateway 回應：$HTTP_STATUS（可能需要再等幾秒）"

# ── STEP 10：Telegram 配對引導 ───────────────────────────────────────────────
if [ -n "$TG_TOKEN" ]; then
  section "STEP 10｜Telegram 配對"
  echo ""
  echo "  1. 打開 Telegram，搜尋你的 Bot（t.me/你的bot名稱）"
  echo "  2. 發送任意訊息（例如：你好）"
  echo "  3. Bot 回覆 8 位配對碼，格式如：Y9L7C7RG"
  echo ""
  read -r -p "  請貼上配對碼：" PAIRING_CODE
  echo ""

  if [ -n "$PAIRING_CODE" ]; then
    node "$INSTALL_DIR/openclaw.mjs" pairing approve telegram "$PAIRING_CODE" 2>/dev/null \
      && print_ok "配對成功！" \
      || print_warn "配對失敗，請確認配對碼是否正確"
  else
    print_warn "跳過配對，稍後手動執行："
    echo -e "  ${CYAN}sudo node $INSTALL_DIR/openclaw.mjs pairing approve telegram 配對碼${RESET}"
  fi
fi

# ── LINE Webhook 提示 ────────────────────────────────────────────────────────
if [ -n "$LINE_TOKEN" ]; then
  echo ""
  echo "  ── LINE Webhook 設定 ───────────────────────────"
  echo "  Webhook URL：http://${PUBLIC_IP}/line/webhook"
  echo ""
  echo "  填到 LINE Developers Console："
  echo "  Messaging API → Webhook URL → Verify"
  echo "  記得開啟「Use webhook」並關閉「Auto-reply messages」"
fi

# ── 完成 ──────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BLUE}════════════════════════════════════════════${RESET}"
echo -e "  🦞 OpenClaw 自媒體班 部署完成！"
echo -e "${BLUE}════════════════════════════════════════════${RESET}"
echo ""
echo "  傳送 /d01 給 Bot → 開始入學診斷"
echo "  已安裝 Skill 數量：${SKILL_COUNT_FINAL} / 152"
echo ""
echo "  常用指令："
echo "  查看龍蝦狀態    sudo systemctl status openclaw"
echo "  重新啟動龍蝦    sudo systemctl restart openclaw"
echo "  查看即時 log    sudo journalctl -u openclaw -f"
echo ""
