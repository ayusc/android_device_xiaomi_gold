#!/usr/bin/env bash

set -eo pipefail

if [ -t 1 ]; then
    CYAN='\033[0;36m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    RED='\033[0;31m'
    BLUE='\033[0;34m'
    BOLD='\033[1m'
    RESET='\033[0m'
else
    CYAN='' GREEN='' YELLOW='' RED='' BLUE='' BOLD='' RESET=''
fi

LOG_INFO="${BLUE}[INFO]${RESET}"
LOG_ACT="${CYAN}[ACTION]${RESET}"
LOG_OK="${GREEN}[OK]${RESET}"
LOG_WARN="${YELLOW}[WARN]${RESET}"
LOG_ERR="${RED}[FAIL]${RESET}"

EXPECTED_PRELOADER_SHA1="40e3c4d31163474cb2e945ab5670e6b807677358"
EXPECTED_LK_SHA1="c691bbda11e67699bb856773137b769ff07c670a"

calculate_sha1() {
    local target="$1"
    if command -v sha1sum &> /dev/null; then
        sha1sum "$target" | awk '{print $1}'
    elif command -v shasum &> /dev/null; then
        shasum -a 1 "$target" | awk '{print $1}'
    else
        openssl dgst -sha1 "$target" | awk '{print $NF}'
    fi
}

clear
echo -e "${CYAN}${BOLD}"
cat << "EOF"
  ____  _     _               ___  ____  
 |  _ \(_)___(_)_ __   __ _/ _ \/ ___| 
 | |_) | / __| | '_ \ / _` | | | \___ \ 
 |  _ <| \__ \ | | | | (_| | |_| |___) |
 |_| \_\_|___/_|_| |_|\__, |\___/|____/ 
                       |___/             
EOF
echo -e "${RESET}${BOLD}          Community Installer | Script by Ayus${RESET}\n"

echo -e "${LOG_INFO} Initializing target device verification..."
if ! command -v fastboot &> /dev/null; then
    echo -e "${LOG_ERR} Fastboot binary missing from system PATH."
    exit 1
fi

if ! fastboot devices | grep -q 'fastboot'; then
    echo -e "${LOG_ERR} Target device not detected in fastboot mode."
    exit 1
fi

DEVICE_CODENAME=$(fastboot getvar product 2>&1 | awk -F': ' '/product/ {print $2}' | tr -d '\r')
DEVICE_SERIAL=$(fastboot getvar serialno 2>&1 | awk -F': ' '/serialno/ {print $2}' | tr -d '\r')
CURRENT_SLOT=$(fastboot getvar current-slot 2>&1 | grep -oE 'current-slot:[[:space:]]*[ab]' | awk '{print $NF}' | tr -d '\r')
CURRENT_SLOT=${CURRENT_SLOT:-a}
OTHER_SLOT=$([ "$CURRENT_SLOT" = "a" ] && echo "b" || echo "a")

echo -e "${LOG_OK} Target identified: ${BOLD}${DEVICE_CODENAME:-Unknown}${RESET} (${DEVICE_SERIAL:-Unknown})"
echo -e "${LOG_OK} Active slot: ${BOLD}${CURRENT_SLOT}${RESET} | Inactive slot: ${BOLD}${OTHER_SLOT}${RESET}\n"

echo -e "${LOG_INFO} Validating trusted bootloader components via SHA-1..."

PRELOADER_IMG=""
if [ -f "preloader_raw.img" ]; then
    PRELOADER_IMG="preloader_raw.img"
elif [ -f "preloader.img" ]; then
    PRELOADER_IMG="preloader.img"
else
    echo -e "${LOG_ERR} Abort: Missing preloader image (preloader_raw.img / preloader.img)."
    exit 1
fi

ACTUAL_PRELOADER_SHA1=$(calculate_sha1 "$PRELOADER_IMG")
if [ "${ACTUAL_PRELOADER_SHA1,,}" != "${EXPECTED_PRELOADER_SHA1,,}" ]; then
    echo -e "${LOG_ERR} Abort: Preloader SHA-1 mismatch for ${PRELOADER_IMG}!"
    echo -e "       Expected: ${EXPECTED_PRELOADER_SHA1}"
    echo -e "       Found:    ${ACTUAL_PRELOADER_SHA1}"
    exit 1
fi
echo -e "${LOG_OK} Verified trusted preloader (${PRELOADER_IMG}): ${ACTUAL_PRELOADER_SHA1}"

if [ ! -f "lk.img" ]; then
    echo -e "${LOG_ERR} Abort: Missing Little Kernel image (lk.img)."
    exit 1
fi

ACTUAL_LK_SHA1=$(calculate_sha1 "lk.img")
if [ "${ACTUAL_LK_SHA1,,}" != "${EXPECTED_LK_SHA1,,}" ]; then
    echo -e "${LOG_ERR} Abort: Little Kernel SHA-1 mismatch for lk.img!"
    echo -e "       Expected: ${EXPECTED_LK_SHA1}"
    echo -e "       Found:    ${ACTUAL_LK_SHA1}"
    exit 1
fi
echo -e "${LOG_OK} Verified trusted Little Kernel (lk.img): ${ACTUAL_LK_SHA1}"

FW_PARTITIONS=("dpm" "gz" "mcupm" "md1img" "pi_img" "scp" "spmfw" "sspm" "tee")
STATIC_PARTITIONS=("boot" "dtbo" "vendor_boot" "vbmeta" "vbmeta_system" "vbmeta_vendor")
LOGICAL_PARTITIONS=("odm_dlkm" "product" "system" "system_dlkm" "system_ext" "vendor" "vendor_dlkm")

echo -e "\n${BOLD}Select Flashing Mode:${RESET}"
echo "  [1] Clean Flash (Format userdata & metadata - Highly Recommended)"
echo "  [2] Dirty Flash (Retain existing userdata)"
read -rp "Option [1/2, default: 1]: " WIPE_CHOICE
WIPE_CHOICE=${WIPE_CHOICE:-1}

echo ""
read -rp "Enable bootloader spoofing ? [Y/n] (default: Y): " SPOOF_CHOICE
SPOOF_CHOICE=${SPOOF_CHOICE:-Y}

echo ""
read -rp "Press [ENTER] to start flashing..."
echo ""

echo -e "${LOG_ACT} Flashing trusted preloader (${PRELOADER_IMG})..."
fastboot flash preloader "${PRELOADER_IMG}" >/dev/null 2>&1
echo -e "${LOG_OK} Preloader written."

echo -e "${LOG_ACT} Flashing trusted Little Kernel (lk.img)..."
fastboot flash lk lk.img >/dev/null 2>&1 || (fastboot flash lk_a lk.img >/dev/null 2>&1 && fastboot flash lk_b lk.img >/dev/null 2>&1)
echo -e "${LOG_OK} Little Kernel written."

echo -e "${LOG_INFO} Writing firmware packages..."
for fw in "${FW_PARTITIONS[@]}"; do
    if [ -f "${fw}.img" ]; then
        echo -e "${LOG_ACT} Flashing ${fw}..."
        fastboot flash "${fw}" "${fw}.img" >/dev/null 2>&1
    fi
done

echo -e "${LOG_INFO} Writing dual-slot static partitions..."
for part in "${STATIC_PARTITIONS[@]}"; do
    if [ -f "${part}.img" ]; then
        echo -e "${LOG_ACT} Flashing ${part} (slots ${CURRENT_SLOT}, ${OTHER_SLOT})..."
        fastboot flash "${part}_${CURRENT_SLOT}" "${part}.img" >/dev/null 2>&1
        fastboot flash "${part}_${OTHER_SLOT}" "${part}.img" >/dev/null 2>&1
    fi
done

echo -e "\n${LOG_INFO} Transitioning target to userspace daemon (fastbootd)..."
fastboot reboot fastboot >/dev/null 2>&1

echo -n -e "${LOG_INFO} Awaiting fastbootd handshake"
while true; do
    IS_USERSPACE=$(fastboot getvar is-userspace 2>&1 | awk -F': ' '/is-userspace/ {print $2}' | tr -d '\r')
    if [ "$IS_USERSPACE" = "yes" ]; then
        break
    fi
    echo -n "."
    sleep 2
done
echo -e " ${GREEN}[ONLINE]${RESET}"

echo -e "${LOG_INFO} Purging deprecated logical tables..."
for part in "${LOGICAL_PARTITIONS[@]}"; do
    fastboot delete-logical-partition "${part}_a-cow" >/dev/null 2>&1 || true
    fastboot delete-logical-partition "${part}_b-cow" >/dev/null 2>&1 || true
    fastboot delete-logical-partition "${part}_a" >/dev/null 2>&1 || true
    fastboot delete-logical-partition "${part}_b" >/dev/null 2>&1 || true
done
for p in cust cust_a cust_b mi_ext mi_ext_a mi_ext_b; do
    fastboot delete-logical-partition "$p" >/dev/null 2>&1 || true
done
echo -e "${LOG_OK} Dynamic allocations cleared."

echo -e "${LOG_INFO} Allocating and writing logical partitions (Slot: ${CURRENT_SLOT})..."
for part in "${LOGICAL_PARTITIONS[@]}"; do
    img="${part}.img"
    if [ -f "$img" ]; then
        echo -e "${LOG_ACT} Flashing ${part}_${CURRENT_SLOT}..."
        fastboot create-logical-partition "${part}_${CURRENT_SLOT}" 0 >/dev/null 2>&1 || true
        fastboot flash "${part}_${CURRENT_SLOT}" "${img}" >/dev/null 2>&1
    else
        echo -e "${LOG_WARN} Skipping optional logical: ${img}"
    fi
done

echo -e "\n${LOG_INFO} Applying final configurations..."
if [ "$WIPE_CHOICE" = "1" ]; then
    echo -e "${LOG_ACT} Formatting userdata and metadata..."
    fastboot -w >/dev/null 2>&1 || fastboot erase userdata >/dev/null 2>&1 || true
    fastboot erase metadata >/dev/null 2>&1 || true
    echo -e "${LOG_OK} User data cleared."
fi

echo -e "${LOG_ACT} Setting active boot slot: ${CURRENT_SLOT}..."
fastboot set_active "$CURRENT_SLOT" >/dev/null 2>&1

if [[ "$SPOOF_CHOICE" =~ ^[Yy]$ ]]; then
    echo -e "${LOG_ACT} Enabling bootloader spoofing..."
    fastboot oem bldr_spoof on >/dev/null 2>&1 || true
fi

echo -e "\n${GREEN}${BOLD}========================================================"
echo -e "          Flash Completed Successfully          "
echo -e "========================================================${RESET}\n"

read -rp "Press [ENTER] to reboot into RisingOS..."
fastboot reboot
