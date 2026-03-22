#!/bin/bash
set -euo pipefail
# =============================================================================
#  🦞  OpenClaw VM 一鍵建立腳本（GCP 版）
#      自媒體班 備案方案
#
#  適用場景：Oracle Cloud 申請不過時的備案
#
#  費用說明：
#    GCP 沒有永久免費的足夠規格
#    本腳本建立 e2-medium（2 vCPU / 4GB RAM）
#    費用約 NT$700–900 /月（asia-east1 台灣區）
#    若選新加坡區（asia-southeast1）約 NT$650–800/月
#
#  在 GCP Cloud Shell 執行：
#    curl -fsSL https://raw.githubusercontent.com/Joanna8521/openclaw-install_ecom/main/setup_vm_gcp.sh | bash
#
#  自動完成：
#    1. 確認 gcloud 設定和專案
#    2. 啟用必要 API
#    3. 建立 VM（e2-medium / Ubuntu 22.04 / asia-east1）
#    4. 開放防火牆 Port 80 + 443
#    5. 輸出 SSH 連線指令 + 下一步提示
# =============================================================================

# ── 顏色 ────────────────────────────────────────────────────────────────────
RED='\033[0;31m';GREEN='\033[0;32m';YELLOW='\033[1;33m'
CYAN='\033[0;36m';BOLD='\033[1m';DIM='\033[2m';NC='\033[0m'

ok()   { echo -e "  ${GREEN}✅${NC}  $1"; }
info() { echo -e "  ${DIM}▸${NC}  $1"; }
warn() { echo -e "  ${YELLOW}⚠️ ${NC}  $1"; }
err()  { echo -e "  ${RED}❌${NC}  $1"; exit 1; }
section() {
  echo ""
  echo -e "${BOLD}${CYAN}════════════════════════════════════════════${NC}"
  echo -e "${BOLD}${CYAN}  $1${NC}"
  echo -e "${BOLD}${CYAN}════════════════════════════════════════════${NC}"
  echo ""
}

# ── 預設設定 ─────────────────────────────────────────────────────────────────
VM_NAME="openclaw-media-vm"
MACHINE_TYPE="e2-medium"          # 2 vCPU / 4GB RAM
REGION="asia-east1"               # 台灣（較近、延遲低）
ZONE="asia-east1-b"
IMAGE_FAMILY="ubuntu-2204-lts"
IMAGE_PROJECT="ubuntu-os-cloud"
DISK_SIZE="30GB"
FIREWALL_TAG="openclaw-media"

# ── Banner ──────────────────────────────────────────────────────────────────
clear
echo -e "${BOLD}${CYAN}"
cat << 'BANNER'
  ╔═══════════════════════════════════════════╗
  ║                                           ║
  ║     🦞  OpenClaw VM 一鍵建立程式          ║
  ║         自媒體班 × GCP 備案方案           ║
  ║                                           ║
  ╚═══════════════════════════════════════════╝
BANNER
echo -e "${NC}"
echo "  ⚠️  費用提醒："
echo "  GCP 沒有永久免費的足夠規格。"
echo "  本腳本建立 e2-medium（2 vCPU / 4GB RAM / 台灣區）"
echo '  費用約 NT\$700–900 / 月（不含流量）'
echo ""
echo "  Oracle Cloud 是零成本的首選方案。"
echo "  如果 Oracle 申請不過，再使用 GCP 備案。"
echo ""
echo "  替代考量："
echo "  Hetzner Cloud CX22（新加坡）2 vCPU / 4GB / NT$140/月"
echo "  → 比 GCP 便宜 5 倍，申請也更簡單（信用卡即可）"
echo ""
read -rp "  確認要繼續用 GCP 建立 VM？[y/N] " confirm
[[ "${confirm,,}" == "y" ]] || { echo "  已取消"; exit 0; }

# ── STEP 1：確認 gcloud 環境 ─────────────────────────────────────────────────
section "STEP 1｜確認 GCP 環境"

if ! command -v gcloud &>/dev/null; then
  err "找不到 gcloud。請在 GCP Cloud Shell 執行此腳本，或安裝 gcloud CLI。"
fi
ok "gcloud CLI 已就緒"

# 取得目前專案
PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
if [[ -z "$PROJECT_ID" ]]; then
  echo ""
  warn "尚未設定 GCP 專案"
  echo ""
  echo "  請先建立或選擇一個 GCP 專案："
  echo "  1. 前往 console.cloud.google.com"
  echo "  2. 點選頂部的專案選單 → 建立專案"
  echo "  3. 建立後在 Cloud Shell 執行：gcloud config set project 你的PROJECT_ID"
  echo ""
  read -rp "  請輸入你的 Project ID: " PROJECT_ID
  [[ -z "$PROJECT_ID" ]] && err "Project ID 不能為空"
  gcloud config set project "$PROJECT_ID"
fi
ok "GCP 專案：$PROJECT_ID"

# 確認帳單已啟用（建 VM 需要）
info "確認帳單狀態..."
BILLING=$(gcloud beta billing projects describe "$PROJECT_ID" \
  --format="value(billingEnabled)" 2>/dev/null || echo "false")
if [[ "$BILLING" != "True" ]]; then
  warn "此專案尚未啟用帳單（Billing）"
  echo ""
  echo "  建立 VM 需要啟用帳單，即使使用免費試用額度也需要綁定信用卡。"
  echo "  前往：console.cloud.google.com/billing"
  echo "  啟用後重新執行此腳本。"
  exit 1
fi
ok "帳單已啟用"

# ── STEP 2：啟用必要 API ─────────────────────────────────────────────────────
section "STEP 2｜啟用必要 API"

info "啟用 Compute Engine API（首次約需 30 秒）..."
gcloud services enable compute.googleapis.com --project="$PROJECT_ID" 2>/dev/null || true
ok "Compute Engine API 已啟用"

# ── STEP 3：選擇區域 ─────────────────────────────────────────────────────────
section "STEP 3｜選擇區域"

echo "  建議區域："
echo '  1) asia-east1-b     台灣（延遲最低，約 NT\$750/月）'
echo '  2) asia-southeast1-b 新加坡（費用略低，約 NT\$680/月）'
echo "  3) 自訂"
echo ""
read -rp "  選擇 [1/2/3，預設 1]: " region_choice

case "${region_choice:-1}" in
  2)
    REGION="asia-southeast1"
    ZONE="asia-southeast1-b"
    ;;
  3)
    read -rp "  請輸入 Zone（例如 us-central1-a）: " ZONE
    REGION=$(echo "$ZONE" | sed 's/-[a-z]$//')
    ;;
  *)
    REGION="asia-east1"
    ZONE="asia-east1-b"
    ;;
esac
ok "區域：$ZONE"

# ── STEP 4：確認 VM 不重複 ───────────────────────────────────────────────────
section "STEP 4｜確認環境"

info "檢查是否已有同名 VM..."
EXISTING=$(gcloud compute instances list \
  --filter="name=$VM_NAME AND zone:$ZONE" \
  --format="value(name)" 2>/dev/null || echo "")

if [[ -n "$EXISTING" ]]; then
  warn "偵測到同名 VM「$VM_NAME」已存在於 $ZONE"
  echo ""
  read -rp "  要刪掉舊的重新建立嗎？[y/N] " del_confirm
  if [[ "${del_confirm,,}" == "y" ]]; then
    info "刪除舊 VM..."
    gcloud compute instances delete "$VM_NAME" \
      --zone="$ZONE" --quiet 2>/dev/null
    ok "舊 VM 已刪除"
  else
    echo "  已取消。如需使用現有 VM，請直接 SSH 進去跑 bootstrap.sh"
    exit 0
  fi
fi

# ── STEP 5：建立防火牆規則 ───────────────────────────────────────────────────
section "STEP 5｜設定防火牆"

FW_RULE="allow-openclaw-media"
EXISTING_FW=$(gcloud compute firewall-rules list \
  --filter="name=$FW_RULE" \
  --format="value(name)" 2>/dev/null || echo "")

if [[ -z "$EXISTING_FW" ]]; then
  info "建立防火牆規則（開放 Port 80 + 443）..."
  gcloud compute firewall-rules create "$FW_RULE" \
    --project="$PROJECT_ID" \
    --direction=INGRESS \
    --priority=1000 \
    --network=default \
    --action=ALLOW \
    --rules=tcp:80,tcp:443 \
    --source-ranges=0.0.0.0/0 \
    --target-tags="$FIREWALL_TAG" \
    --description="OpenClaw 自媒體班 LINE Webhook + HTTPS" 2>/dev/null
  ok "防火牆規則建立完成（Port 80 + 443 開放）"
else
  ok "防火牆規則已存在，跳過"
fi

# ── STEP 6：建立 VM ──────────────────────────────────────────────────────────
section "STEP 6｜建立 VM（e2-medium / Ubuntu 22.04）"

info "建立 VM，約需 30–60 秒..."
gcloud compute instances create "$VM_NAME" \
  --project="$PROJECT_ID" \
  --zone="$ZONE" \
  --machine-type="$MACHINE_TYPE" \
  --image-family="$IMAGE_FAMILY" \
  --image-project="$IMAGE_PROJECT" \
  --boot-disk-size="$DISK_SIZE" \
  --boot-disk-type="pd-standard" \
  --tags="$FIREWALL_TAG,http-server,https-server" \
  --metadata="enable-oslogin=false" \
  --no-address=false 2>/dev/null

ok "VM 建立完成！"

# ── STEP 7：取得 VM 資訊 ─────────────────────────────────────────────────────
section "STEP 7｜取得連線資訊"

info "取得 VM 公網 IP..."
PUBLIC_IP=$(gcloud compute instances describe "$VM_NAME" \
  --zone="$ZONE" \
  --format="value(networkInterfaces[0].accessConfigs[0].natIP)" 2>/dev/null)

if [[ -z "$PUBLIC_IP" ]]; then
  warn "無法取得 Public IP，請手動確認"
  PUBLIC_IP="<請至 GCP Console 查看 VM 的 External IP>"
fi
ok "Public IP：$PUBLIC_IP"

# ── 完成畫面 ─────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${GREEN}"
cat << 'SUCCESS'
  ╔═══════════════════════════════════════════╗
  ║                                           ║
  ║     🎉  VM 建立完成！                     ║
  ║                                           ║
  ╚═══════════════════════════════════════════╝
SUCCESS
echo -e "${NC}"

echo "  ── VM 資訊 ─────────────────────────────────"
echo "  VM 名稱：$VM_NAME"
echo "  區域：   $ZONE"
echo "  規格：   e2-medium（2 vCPU / 4GB RAM）"
echo "  IP：     $PUBLIC_IP"
echo ""
echo "  ── 下一步：SSH 進去安裝龍蝦 ────────────────"
echo ""
echo "  方法一（GCP Cloud Shell 直接連）："
echo "  gcloud compute ssh $VM_NAME --zone=$ZONE"
echo ""
echo "  方法二（本機 SSH）："
echo "  gcloud compute config-ssh"
echo "  ssh $VM_NAME.$ZONE.$PROJECT_ID"
echo ""
echo "  ── 進入 VM 後，貼上以下指令安裝龍蝦 ────────"
echo ""
echo "  curl -fsSL https://raw.githubusercontent.com/Joanna8521/openclaw-install_ecom/main/bootstrap.sh | sudo bash"
echo ""
echo "  ── ⚠️  費用提醒 ──────────────────────────────"
echo '  GCP VM 費用：約 NT\$700–900 / 月'
echo "  如不使用時，可在 GCP Console 停止 VM 暫停計費"
echo "  （停止後不計 CPU/RAM 費用，只計磁碟費用約 NT$30/月）"
echo ""
echo "  ── LINE Webhook 設定 ────────────────────────"
echo "  Webhook URL：http://$PUBLIC_IP/line/webhook"
echo "  （安裝完龍蝦後再設定，需要 HTTPS 可用 ngrok）"
echo ""
