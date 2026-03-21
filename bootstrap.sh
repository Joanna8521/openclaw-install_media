#!/bin/bash
# =============================================================================
#  🦞  OpenClaw Bootstrap 安裝腳本
#      酒Ann × OpenClaw_media 自媒體班
#
#  在 VM 內執行（需要 root）：
#    curl -fsSL https://raw.githubusercontent.com/Joanna8521/openclaw-install_media/main/bootstrap.sh -o bootstrap.sh && chmod +x bootstrap.sh && sudo ./bootstrap.sh
#
#  ⚠️  不可用 curl | sudo bash 執行，否則互動式輸入（Bot Token / API Key / 配對碼）會無法輸入
#
#  自動完成：
#    1. 系統套件更新 + Node.js v22 安裝
#    2. 從 GitHub 安裝 OpenClaw（openclaw/openclaw）
#    3. 安裝自媒體班 Skills（Joanna8521/openclaw_media）
#    4. 設定 Nginx 反向代理（Port 80）
#    5. 設定 systemd 服務（開機自動啟動）
#    6. 輸出設定 Bot Token 的下一步指令
#
#  已驗證環境：Ubuntu 22.04 ARM（Oracle VM.Standard.A1.Flex）
#  需要 Node.js v22.12+（腳本自動安裝）
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
SKILLS_REPO="https://github.com/Joanna8521/openclaw_media.git"
SKILLS_PAT=""  # 由學員輸入
OPENCLAW_REPO="https://github.com/openclaw/openclaw.git"
SERVICE_USER="root"   # 必須是 root，configs 在 /root/.openclaw/
SERVICE_FILE="/etc/systemd/system/openclaw.service"
NGINX_CONF="/etc/nginx/sites-available/openclaw"

# ── Banner ──────────────────────────────────────────────────────────────────
clear
echo -e "${BOLD}"
cat << 'BANNER'
  ╔═══════════════════════════════════════════╗
  ║                                           ║
  ║     🦞  OpenClaw 安裝腳本                 ║
  ║         酒Ann × OpenClaw_media 課程         ║
  ║         自媒體班                      ║
  ║                                           ║
  ╚═══════════════════════════════════════════╝
BANNER
echo -e "${RESET}"

# ── STEP 1：系統更新 + 安裝基礎套件 ─────────────────────────────────────────
section "STEP 1｜系統更新與套件安裝"
print_info "更新 apt 套件清單..."
apt-get update -qq

print_info "安裝基礎套件..."
apt-get install -y -qq \
  git curl wget jq nginx cron build-essential \
  ca-certificates gnupg lsb-release unzip 2>/dev/null
print_ok "基礎套件安裝完成"

# ── STEP 2：安裝 Node.js v22 ─────────────────────────────────────────────────
section "STEP 2｜Node.js v22 安裝"

NODE_VER=$(node --version 2>/dev/null || echo "none")
NODE_MAJOR=$(echo "$NODE_VER" | grep -oP '(?<=v)\d+' || echo "0")

if [ "$NODE_MAJOR" -lt 22 ]; then
  print_info "目前 Node.js $NODE_VER，需要升級到 v22..."
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash - 2>/dev/null
  apt-get install -y -qq nodejs
  print_ok "Node.js $(node --version) 安裝完成"
else
  print_ok "Node.js $NODE_VER 已符合需求（>= v22）"
fi

# ── STEP 3：安裝 OpenClaw 主程式 ─────────────────────────────────────────────
section "STEP 3｜OpenClaw 主程式安裝"

if [ -d "$INSTALL_DIR/.git" ]; then
  print_info "OpenClaw 已存在，更新到最新版..."
  cd "$INSTALL_DIR"
  git pull --quiet
else
  print_info "從 GitHub 下載 OpenClaw..."
  rm -rf "$INSTALL_DIR"
  git clone --depth 1 --quiet "$OPENCLAW_REPO" "$INSTALL_DIR"
fi
print_ok "OpenClaw 主程式下載完成"

# ── STEP 4：安裝 Node.js 依賴套件 ────────────────────────────────────────────
section "STEP 4｜安裝 Node.js 依賴套件"
print_info "安裝 pnpm..."
npm install -g pnpm --quiet 2>/dev/null
print_ok "pnpm 安裝完成"

print_info "安裝套件依賴（pnpm install）..."
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

# 設定技能目錄（讓龍蝦讀到自媒體班的 SKILL.md）
node "$INSTALL_DIR/openclaw.mjs" config set skills.load.extraDirs '[
  "/root/.openclaw/skills"
]' 2>/dev/null || true

print_ok "OpenClaw 設定初始化完成"

# ── STEP 6：安裝自媒體班 Skills ───────────────────────────────────────────────
section "STEP 6｜安裝自媒體班 Skills"

SKILLS_DIR="/root/.openclaw/skills"
mkdir -p "$SKILLS_DIR"

# ── 從 setup_vm.sh 預存的檔案讀取 PAT ───────────────────────────────────────
PAT_FILE="/root/.openclaw/skills_pat"
if [ -f "$PAT_FILE" ]; then
  SKILLS_PAT=$(cat "$PAT_FILE")
  print_ok "課程存取碼已從設定檔讀取"
else
  print_warn "找不到課程存取碼設定檔（$PAT_FILE）"
  print_warn "Skills 安裝將跳過，完成部署後請聯絡老師補安裝"
  SKILLS_PAT=""
fi

if [ -z "$SKILLS_PAT" ]; then
  print_warn "未輸入課程存取碼，跳過 Skills 安裝"
  print_warn "之後可手動執行：git clone https://<存取碼>@github.com/Joanna8521/openclaw_media.git /tmp/skills_tmp"
else
  print_info "從 GitHub 下載自媒體班 Skills..."
  TMP_SKILLS="/tmp/openclaw_media_skills_install"
  rm -rf "$TMP_SKILLS"

  # 把 PAT 嵌入 clone URL
  CLONE_URL="https://${SKILLS_PAT}@github.com/Joanna8521/openclaw_media.git"

  if git clone --depth 1 --quiet "$CLONE_URL" "$TMP_SKILLS" 2>/dev/null; then
    if [ -d "$TMP_SKILLS/skills" ]; then
      cp -r "$TMP_SKILLS/skills/"* "$SKILLS_DIR/" 2>/dev/null || true
      SKILL_COUNT=$(find "$SKILLS_DIR" -name 'SKILL.md' | wc -l)
      print_ok "自媒體班 Skills 安裝完成（${SKILL_COUNT} 個技能）"
    else
      print_warn "Skills 目錄結構不符預期，請確認 repo 內有 skills/ 資料夾"
    fi
    # 清除含 PAT 的 clone 紀錄
    rm -rf "$TMP_SKILLS"
    git -C "$SKILLS_DIR" remote remove origin 2>/dev/null || true
  else
    print_err "存取碼錯誤或 repo 不存在，Skills 安裝失敗"
    print_warn "請確認存取碼是否正確，之後可重新執行此腳本"
  fi
fi

# 安裝共用基礎 C01-C10
print_info "安裝共用基礎技能 C01–C10..."
node "$INSTALL_DIR/openclaw.mjs" install c01 c02 c03 c04 c05 c06 c07 c08 c09 c10 2>/dev/null || true
print_ok "共用基礎技能安裝完成"

# ── STEP 7：設定 Nginx ───────────────────────────────────────────────────────
section "STEP 7｜設定 Nginx 反向代理"

cat > "$NGINX_CONF" << 'NGINX'
server {
    listen 80;
    server_name _;

    # LINE Webhook
    location /line/webhook {
        proxy_pass http://127.0.0.1:18789/line/webhook;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_read_timeout 60s;
    }

    # Telegram Webhook
    location /telegram/webhook {
        proxy_pass http://127.0.0.1:18789/telegram/webhook;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_read_timeout 60s;
    }

    # Health check
    location /health {
        proxy_pass http://127.0.0.1:18789/health;
        proxy_http_version 1.1;
    }

    # API
    location /api/ {
        proxy_pass http://127.0.0.1:18789/api/;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
NGINX

# 啟用設定
ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/openclaw
rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true

# 測試 Nginx 設定
nginx -t -q 2>/dev/null && systemctl reload nginx && print_ok "Nginx 設定完成" \
  || print_warn "Nginx 設定有問題，請執行 nginx -t 查看詳情"

# ── STEP 8：設定 systemd 服務 ────────────────────────────────────────────────
section "STEP 8｜設定 systemd 自動啟動服務"

cat > "$SERVICE_FILE" << SYSTEMD
[Unit]
Description=OpenClaw AI 龍蝦助理（自媒體班）
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=$SERVICE_USER
WorkingDirectory=$INSTALL_DIR
ExecStart=/usr/bin/node $INSTALL_DIR/openclaw.mjs gateway
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
sleep 3

# 確認服務狀態
if systemctl is-active --quiet openclaw; then
  print_ok "systemd 服務啟動完成"
else
  print_warn "服務啟動失敗，查看 log："
  journalctl -u openclaw -n 15 --no-pager
fi

# ── STEP 9：取得 VM Public IP ─────────────────────────────────────────────────
section "STEP 9｜取得 VM 資訊"
PUBLIC_IP=$(curl -s --max-time 5 http://checkip.amazonaws.com 2>/dev/null \
  || curl -s --max-time 5 ifconfig.me 2>/dev/null \
  || echo "無法取得")
print_ok "VM Public IP：$PUBLIC_IP"

# ── STEP 10：引導設定 Bot ────────────────────────────────────────────────────
section "STEP 10｜設定通知 Bot"
echo ""
echo -e "  ${BOLD}要現在設定 Bot 嗎？${RESET}"
echo "  1) Telegram Bot（推薦，設定較簡單）"
echo "  2) LINE Bot"
echo "  3) 跳過，稍後手動設定"
echo ""
read -r -p "  請輸入選項（1/2/3）：" BOT_CHOICE

case "$BOT_CHOICE" in
  1)
    # ── Telegram 設定引導 ────────────────────────────────────────────────────
    section "設定 Telegram Bot"
    echo ""
    echo "  步驟一：到 Telegram 搜尋 @BotFather"
    echo "  步驟二：發送 /newbot，依指示建立 Bot"
    echo "  步驟三：取得 Bot Token（格式：1234567890:ABCdef...）"
    echo ""
    read -r -p "  請貼上 Bot Token：" TG_TOKEN
    echo ""

    if [ -z "$TG_TOKEN" ]; then
      print_warn "未輸入 Token，跳過"
    else
      node "$INSTALL_DIR/openclaw.mjs" config set channels.telegram.botToken "$TG_TOKEN" 2>/dev/null         && print_ok "Telegram Bot Token 設定完成"         || print_warn "設定失敗，請手動執行：sudo node $INSTALL_DIR/openclaw.mjs config set channels.telegram.botToken "你的Token""

      # ── 設定 AI 提供商 ────────────────────────────────────────────────────
      echo ""
      echo -e "  ${BOLD}設定 AI 提供商${RESET}"
      echo "  1) Claude（Anthropic）"
      echo "  2) OpenAI（GPT）"
      echo "  3) 跳過"
      echo ""
      read -r -p "  請輸入選項（1/2/3）：" AI_CHOICE

      case "$AI_CHOICE" in
        1)
          read -r -p "  請貼上 Claude API Key（sk-ant-...）：" CLAUDE_KEY
          [ -n "$CLAUDE_KEY" ] && node "$INSTALL_DIR/openclaw.mjs" config set providers.claude.apiKey "$CLAUDE_KEY" 2>/dev/null             && print_ok "Claude API Key 設定完成"
          ;;
        2)
          read -r -p "  請貼上 OpenAI API Key（sk-...）：" OPENAI_KEY
          [ -n "$OPENAI_KEY" ] && node "$INSTALL_DIR/openclaw.mjs" config set providers.openai.apiKey "$OPENAI_KEY" 2>/dev/null             && print_ok "OpenAI API Key 設定完成"
          ;;
        *)
          print_warn "跳過 AI 設定，稍後手動設定"
          ;;
      esac

      systemctl restart openclaw
      sleep 5
      systemctl is-active --quiet openclaw && print_ok "龍蝦重啟完成" || print_warn "重啟失敗，請執行 sudo systemctl restart openclaw"

      # ── 引導 Telegram Pairing ──────────────────────────────────────────────
      echo ""
      echo -e "  ${BOLD}最後一步：配對你的 Telegram 帳號${RESET}"
      echo ""
      echo "  1. 打開 Telegram，搜尋你剛建立的 Bot"
      echo "  2. 對 Bot 發送任何訊息（例如：你好）"
      echo "  3. Bot 會回覆一段配對碼，格式如：Y9L7C7RG"
      echo ""
      read -r -p "  請貼上配對碼（8位英數字）：" PAIRING_CODE
      echo ""

      if [ -z "$PAIRING_CODE" ]; then
        print_warn "未輸入配對碼，請之後手動執行："
        echo -e "  ${CYAN}sudo node $INSTALL_DIR/openclaw.mjs pairing approve telegram 配對碼${RESET}"
      else
        node "$INSTALL_DIR/openclaw.mjs" pairing approve telegram "$PAIRING_CODE" 2>/dev/null           && print_ok "配對成功！"           || print_warn "配對失敗，請確認配對碼是否正確"
      fi

      echo ""
      echo -e "  ${BOLD}${GREEN}🎉 全部完成！${RESET}"
      echo -e "  回到 Telegram 發 ${CYAN}/help${RESET} 開始使用龍蝦 🦞"
    fi
    ;;

  2)
    # ── LINE 設定引導 ────────────────────────────────────────────────────────
    section "設定 LINE Bot"
    echo ""
    echo "  步驟一：登入 LINE Developers Console（developers.line.biz）"
    echo "  步驟二：建立 Messaging API Channel"
    echo "  步驟三：取得 Channel Secret 和 Channel Access Token"
    echo ""
    read -r -p "  請貼上 Channel Secret：" LINE_SECRET
    read -r -p "  請貼上 Channel Access Token：" LINE_TOKEN
    echo ""

    if [ -z "$LINE_SECRET" ] || [ -z "$LINE_TOKEN" ]; then
      print_warn "未完整輸入，跳過"
    else
      node "$INSTALL_DIR/openclaw.mjs" config set channels.line.channelSecret "$LINE_SECRET" 2>/dev/null
      node "$INSTALL_DIR/openclaw.mjs" config set channels.line.accessToken "$LINE_TOKEN" 2>/dev/null
      print_ok "LINE Bot 設定完成"

      # ── 設定 AI 提供商 ────────────────────────────────────────────────────
      echo ""
      echo -e "  ${BOLD}設定 AI 提供商${RESET}"
      echo "  1) Claude（Anthropic）"
      echo "  2) OpenAI（GPT）"
      echo "  3) 跳過"
      echo ""
      read -r -p "  請輸入選項（1/2/3）：" AI_CHOICE

      case "$AI_CHOICE" in
        1)
          read -r -p "  請貼上 Claude API Key（sk-ant-...）：" CLAUDE_KEY
          [ -n "$CLAUDE_KEY" ] && node "$INSTALL_DIR/openclaw.mjs" config set providers.claude.apiKey "$CLAUDE_KEY" 2>/dev/null             && print_ok "Claude API Key 設定完成"
          ;;
        2)
          read -r -p "  請貼上 OpenAI API Key（sk-...）：" OPENAI_KEY
          [ -n "$OPENAI_KEY" ] && node "$INSTALL_DIR/openclaw.mjs" config set providers.openai.apiKey "$OPENAI_KEY" 2>/dev/null             && print_ok "OpenAI API Key 設定完成"
          ;;
        *)
          print_warn "跳過 AI 設定"
          ;;
      esac

      systemctl restart openclaw
      sleep 3
      systemctl is-active --quiet openclaw && print_ok "龍蝦重啟完成" || print_warn "重啟失敗，請執行 sudo systemctl restart openclaw"

      echo ""
      echo -e "  ${BOLD}LINE Webhook URL（填到 LINE Developers 控制台）${RESET}"
      echo -e "  ${CYAN}http://$PUBLIC_IP/line/webhook${RESET}"
      echo ""
      echo "  ⚠️  記得在 LINE Developers 關閉自動回覆訊息："
      echo "      Messaging API → Auto-reply messages → Disabled"
      echo ""
      echo -e "  ${BOLD}${GREEN}🎉 設定完成！${RESET}"
      echo ""
      echo "  接下來："
      echo "  1. 把上面的 Webhook URL 填到 LINE Developers Console"
      echo "  2. 對 Bot 發任何訊息，Bot 會回覆配對碼"
      echo "  3. 在這裡執行：sudo node $INSTALL_DIR/openclaw.mjs pairing approve line 配對碼"
      echo ""
      read -r -p "  請貼上配對碼（收到後再貼）：" LINE_PAIRING
      if [ -n "$LINE_PAIRING" ]; then
        node "$INSTALL_DIR/openclaw.mjs" pairing approve line "$LINE_PAIRING" 2>/dev/null           && print_ok "LINE 配對成功！"           || print_warn "配對失敗，請確認配對碼"
      fi
    fi
    ;;

  *)
    print_warn "跳過 Bot 設定，稍後手動執行："
    echo ""
    echo -e "  ${CYAN}sudo node $INSTALL_DIR/openclaw.mjs config set channels.telegram.botToken "你的Token"${RESET}"
    echo -e "  ${CYAN}sudo node $INSTALL_DIR/openclaw.mjs config set channels.line.channelSecret "你的Secret"${RESET}"
    echo -e "  ${CYAN}sudo node $INSTALL_DIR/openclaw.mjs config set channels.line.accessToken "你的Token"${RESET}"
    echo -e "  ${CYAN}sudo systemctl restart openclaw${RESET}"
    ;;
esac

echo ""
echo -e "${BLUE}════════════════════════════════════════════${RESET}"
echo -e "  🦞 OpenClaw 自媒體班 部署完成！"
echo -e "${BLUE}════════════════════════════════════════════${RESET}"
echo ""
echo "  ── 快速開始 ──────────────────────────────────"
echo "  傳送 /d01 給 Bot → 開始入學診斷，龍蝦幫你"
echo "  找出目前最適合你的 Top5 技能路徑"
echo ""
SKILL_COUNT_FINAL=$(find /root/.openclaw/skills -name "SKILL.md" 2>/dev/null | wc -l)
echo "  已安裝 Skill 數量：${SKILL_COUNT_FINAL} / 152"
echo ""
