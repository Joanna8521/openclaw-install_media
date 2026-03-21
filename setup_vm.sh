#!/bin/bash
# =============================================================================
#  🦞  OpenClaw VM 一鍵建立腳本
#      酒Ann × OpenClaw_media 自媒體班
#
#  在 Oracle Cloud Shell 執行：
#    curl -fsSL https://raw.githubusercontent.com/Joanna8521/openclaw-install_media/main/setup_vm.sh | bash
#
#  自動完成：
#    1. 產生 SSH 金鑰
#    2. 取得帳號資訊（Compartment、VCN、Subnet、Image）
#    3. 建立 VM.Standard.A1.Flex（4 OCPU / 24GB / Ubuntu 22.04 ARM）
#    4. 開放 Security List Port 22（SSH）和 Port 80（LINE Webhook）
#    5. 輸出完整 SSH 指令 + 下一步提示
#    5. 輸出完整 SSH 指令 + 下一步提示
# =============================================================================
set -euo pipefail

# ── 顏色 ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

print_ok()   { echo -e "  ${GREEN}✅${RESET}  $1"; }
print_info() { echo -e "  ${CYAN}📋${RESET} $1"; }
print_warn() { echo -e "  ${YELLOW}⚠️ ${RESET}  $1"; }
print_err()  { echo -e "  ${RED}❌${RESET}  $1"; }
section()    { echo -e "\n${BLUE}════════════════════════════════════════════${RESET}"; echo -e "  ${BOLD}$1${RESET}"; echo -e "${BLUE}════════════════════════════════════════════${RESET}"; }

# ── Banner ──────────────────────────────────────────────────────────────────
clear
echo -e "${BOLD}"
cat << 'BANNER'
  ╔═══════════════════════════════════════════╗
  ║                                           ║
  ║     🦞  OpenClaw VM 一鍵建立程式          ║
  ║         酒Ann × OpenClaw_media 課程        ║
  ║         自媒體班                      ║
  ║                                           ║
  ╚═══════════════════════════════════════════╝
BANNER
echo -e "${RESET}"

echo "  這個腳本會自動幫你完成："
echo "  1.  產生 SSH 金鑰（登入 VM 用）"
echo "  2.  建立免費 VM（4 OCPU / 24GB RAM / Ubuntu 22.04 ARM）"
echo "  3.  開放 Port 80（LINE Webhook 需要）"
echo "  4.  開放 Port 22（SSH）和 Port 80（LINE Webhook）
  5.  把課程存取碼安全寫入 VM
  6.  輸出完整的安裝指令，直接複製貼上就好"
echo ""
echo "  預計執行時間：約 5 分鐘"
echo ""
read -r -p "  按 Enter 開始 ..."

# ── 確認 OCI 環境 ────────────────────────────────────────────────────────────
section "確認 OCI 環境"
if [ -z "${OCI_TENANCY:-}" ]; then
  print_err "OCI_TENANCY 環境變數不存在，請確認在 Oracle Cloud Shell 執行此腳本"
  exit 1
fi
OCI_TENANCY_ID="$OCI_TENANCY"
print_ok "OCI 環境正常（Tenancy: ${OCI_TENANCY_ID:0:30}...）"

# ── 取得帳號資訊 ─────────────────────────────────────────────────────────────
section "取得帳號資訊"

print_info "取得 Compartment..."
COMPARTMENT_ID=$(oci iam tenancy get \
  --tenancy-id "$OCI_TENANCY_ID" \
  --query 'data.id' --raw-output 2>/dev/null) || {
  print_err "無法取得 Tenancy ID，請確認帳號權限"
  exit 1
}
print_ok "Compartment ID：${COMPARTMENT_ID:0:40}..."

print_info "取得 Availability Domain..."
AD=$(oci iam availability-domain list \
  --compartment-id "$COMPARTMENT_ID" \
  --query 'data[0].name' --raw-output 2>/dev/null) || {
  print_err "無法取得 Availability Domain"
  exit 1
}
print_ok "Availability Domain：$AD"

print_info "搜尋 Ubuntu 22.04 ARM 映像檔..."
IMAGE_ID=$(oci compute image list \
  --compartment-id "$COMPARTMENT_ID" \
  --operating-system "Canonical Ubuntu" \
  --operating-system-version "22.04" \
  --shape "VM.Standard.A1.Flex" \
  --query 'data[0].id' --raw-output 2>/dev/null) || {
  print_err "找不到 Ubuntu 22.04 ARM 映像檔"
  exit 1
}
print_ok "Ubuntu 22.04 ARM Image 找到"

print_info "取得 VCN..."
VCN_ID=$(oci network vcn list \
  --compartment-id "$COMPARTMENT_ID" \
  --query 'data[0].id' --raw-output 2>/dev/null) || {
  print_err "找不到 VCN，請先在 Oracle Cloud 建立 VCN"
  exit 1
}
print_ok "VCN 找到"

print_info "取得 Subnet..."
SUBNET_ID=$(oci network subnet list \
  --compartment-id "$COMPARTMENT_ID" \
  --vcn-id "$VCN_ID" \
  --query 'data[?contains("display-name",`public`) || contains("display-name",`Public`)].id | [0]' \
  --raw-output 2>/dev/null)
if [ -z "$SUBNET_ID" ] || [ "$SUBNET_ID" = "null" ]; then
  SUBNET_ID=$(oci network subnet list \
    --compartment-id "$COMPARTMENT_ID" \
    --vcn-id "$VCN_ID" \
    --query 'data[0].id' --raw-output 2>/dev/null)
fi
print_ok "Public Subnet 找到"

print_info "取得 Security List..."
SL_ID=$(oci network security-list list \
  --compartment-id "$COMPARTMENT_ID" \
  --vcn-id "$VCN_ID" \
  --query 'data[0].id' --raw-output 2>/dev/null)
print_ok "Security List 找到"

# ── 產生 SSH 金鑰 ────────────────────────────────────────────────────────────
section "產生 SSH 金鑰"
SSH_KEY_PATH="$HOME/.ssh/openclaw_media_key"
if [ -f "$SSH_KEY_PATH" ]; then
  print_warn "SSH 金鑰已存在，跳過產生（$SSH_KEY_PATH）"
else
  mkdir -p "$HOME/.ssh"
  ssh-keygen -t rsa -b 4096 -f "$SSH_KEY_PATH" -N "" -q
  print_ok "SSH 金鑰產生完成"
fi
SSH_PUB_KEY=$(cat "${SSH_KEY_PATH}.pub")
print_ok "公鑰已備妥"

# ── 輸入課程存取碼 ────────────────────────────────────────────────────────────
section "輸入課程存取碼（Skills 用）"
echo ""
echo "  課程存取碼格式：github_pat_..."
echo "  （老師提供，輸入後按 Enter）"
echo ""
read -r -p "  課程存取碼：" SKILLS_PAT
echo ""
if [ -z "$SKILLS_PAT" ]; then
  print_warn "未輸入存取碼，跳過（稍後可手動安裝 Skills）"
else
  print_ok "存取碼已記錄，VM 建立後自動寫入"
fi

# ── 確認建立資訊 ─────────────────────────────────────────────────────────────
section "確認 VM 建立資訊"
VM_NAME="openclaw-media-vm"
echo ""
echo "  VM 名稱：$VM_NAME"
echo "  規格：VM.Standard.A1.Flex（4 OCPU / 24 GB RAM）"
echo "  系統：Ubuntu 22.04 ARM"
echo "  Availability Domain：$AD"
echo "  SSH 金鑰：$SSH_KEY_PATH"
echo ""
print_warn "免費方案每個帳號只有 4 OCPU 和 24GB 配額，一台 VM 就用完了"
echo ""
read -r -p "  確認建立？按 Enter 繼續（Ctrl+C 中止）..."

# ── 建立 VM ──────────────────────────────────────────────────────────────────
section "建立 VM（約 2-3 分鐘）"
print_info "正在建立 VM，請稍候..."

INSTANCE_ID=$(oci compute instance launch \
  --compartment-id "$COMPARTMENT_ID" \
  --availability-domain "$AD" \
  --shape "VM.Standard.A1.Flex" \
  --shape-config '{"ocpus": 4, "memoryInGBs": 24}' \
  --image-id "$IMAGE_ID" \
  --subnet-id "$SUBNET_ID" \
  --display-name "$VM_NAME" \
  --assign-public-ip true \
  --ssh-authorized-keys-file "${SSH_KEY_PATH}.pub" \
  --metadata "{\"user_data\": \"\"}" \
  --query 'data.id' --raw-output 2>/dev/null) || {
  print_err "建立 VM 失敗，可能原因：配額不足（帳號需要升級至 PAYG）或 API 權限不足"
  echo ""
  echo "  手動建立方式："
  echo "  Oracle Cloud → Compute → Instances → Create Instance"
  echo "  規格：VM.Standard.A1.Flex / 4 OCPU / 24GB / Ubuntu 22.04"
  exit 1
}
print_ok "VM 建立請求已送出（ID: ${INSTANCE_ID:0:40}...）"

# ── 等待 VM 啟動 ─────────────────────────────────────────────────────────────
print_info "等待 VM 啟動..."
for i in $(seq 1 30); do
  STATE=$(oci compute instance get \
    --instance-id "$INSTANCE_ID" \
    --query 'data."lifecycle-state"' --raw-output 2>/dev/null) || continue
  if [ "$STATE" = "RUNNING" ]; then
    print_ok "VM 已啟動 ✅"
    break
  fi
  echo -ne "  等待中... ($i/30) 狀態：$STATE\r"
  sleep 10
done

# ── 取得 Public IP ────────────────────────────────────────────────────────────
PUBLIC_IP=$(oci compute instance list-vnics \
  --instance-id "$INSTANCE_ID" \
  --compartment-id "$COMPARTMENT_ID" \
  --query 'data[0]."public-ip"' --raw-output 2>/dev/null)

if [ -z "$PUBLIC_IP" ] || [ "$PUBLIC_IP" = "null" ]; then
  print_warn "Public IP 還未分配，稍後在 Oracle Cloud 控制台查看"
  PUBLIC_IP="<VM 的 Public IP>"
fi
print_ok "Public IP：$PUBLIC_IP"

# ── 開放 Port 22 + Port 80 ───────────────────────────────────────────────────
section "開放 Port 22（SSH）和 Port 80（LINE Webhook）"
CURRENT_RULES=$(oci network security-list get \
  --security-list-id "$SL_ID" \
  --query 'data."ingress-security-rules"' 2>/dev/null)

MERGED_RULES=$(echo "$CURRENT_RULES" | python3 -c "
import sys, json
rules = json.load(sys.stdin)
need = [
    {"is-stateless": False, "protocol": "6", "source": "0.0.0.0/0", "source-type": "CIDR_BLOCK",
     "tcp-options": {"destination-port-range": {"max": 22, "min": 22}}},
    {"is-stateless": False, "protocol": "6", "source": "0.0.0.0/0", "source-type": "CIDR_BLOCK",
     "tcp-options": {"destination-port-range": {"max": 80, "min": 80}}},
]
existing_ports = [r.get('tcp-options',{}).get('destination-port-range',{}).get('min') for r in rules]
for rule in need:
    port = rule['tcp-options']['destination-port-range']['min']
    if port not in existing_ports:
        rules.append(rule)
print(json.dumps(rules))
" 2>/dev/null || echo "$CURRENT_RULES")

oci network security-list update \
  --security-list-id "$SL_ID" \
  --ingress-security-rules "$MERGED_RULES" \
  --force 2>/dev/null \
  && print_ok "Port 22（SSH）開放完成" \
  && print_ok "Port 80（LINE Webhook）開放完成" \
  || print_warn "Port 開放失敗，請手動在 Oracle Console 新增 Port 22 和 Port 80"

# ── 備份 SSH 私鑰提示 ─────────────────────────────────────────────────────────
section "備份 SSH 私鑰"
echo "  ⚠️  SSH 私鑰存在 Cloud Shell，重要！請立即備份："
echo ""
echo "  Cloud Shell 右上角選單 → Download file"
echo "  輸入：openclaw_media_key.pem"
echo ""
cp "$SSH_KEY_PATH" "$HOME/openclaw_media_key.pem" 2>/dev/null || true
print_ok "已複製到 ~/openclaw_media_key.pem，可從 Cloud Shell 下載"

# ── 把 PAT 寫入 VM ───────────────────────────────────────────────────────────
if [ -n "$SKILLS_PAT" ] && [ -n "$PUBLIC_IP" ] && [ "$PUBLIC_IP" != "<VM 的 Public IP>" ]; then
  section "把課程存取碼寫入 VM"
  print_info "等待 VM SSH 服務就緒（約 20 秒）..."
  sleep 20
  ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no -o ConnectTimeout=15 \
    ubuntu@"$PUBLIC_IP" \
    "sudo mkdir -p /root/.openclaw && printf '%s' '$SKILLS_PAT' | sudo tee /root/.openclaw/skills_pat > /dev/null && sudo chmod 600 /root/.openclaw/skills_pat" \
    2>/dev/null \
    && print_ok "課程存取碼已安全寫入 VM（/root/.openclaw/skills_pat）" \
    || print_warn "寫入失敗，bootstrap.sh 執行時請手動補安裝 Skills"
fi

# ── 完成！輸出下一步 ──────────────────────────────────────────────────────────
section "🎉 VM 建立完成！下一步"
echo ""
echo -e "  ${BOLD}第一步：SSH 連入 VM${RESET}"
echo ""
echo -e "  ${CYAN}ssh -i $SSH_KEY_PATH ubuntu@$PUBLIC_IP${RESET}"
echo ""
echo -e "  ${BOLD}第二步：進入 VM 後執行安裝腳本${RESET}  ⚠️  請用下面指令（不可用 curl | bash）"
echo ""
echo -e "  ${CYAN}curl -fsSL https://raw.githubusercontent.com/Joanna8521/openclaw-install_media/main/bootstrap.sh -o bootstrap.sh && chmod +x bootstrap.sh && sudo ./bootstrap.sh${RESET}"
echo ""
echo -e "  ${BOLD}第三步：安裝完成後設定 Telegram Bot（或 LINE）${RESET}"
echo ""
echo "  整個過程約 10 分鐘，完成後龍蝦就跑起來了 🦞"
echo ""
echo -e "${BLUE}════════════════════════════════════════════${RESET}"
