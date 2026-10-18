#!/usr/bin/env bash
set -euo pipefail

# --- Colors & Symbols ---
if [ -t 1 ]; then
    BOLD="\033[1m"
    DIM="\033[2m"
    RESET="\033[0m"
    GREEN="\033[32m"
    BLUE="\033[34m"
    YELLOW="\033[33m"
else
    BOLD="" DIM="" RESET="" GREEN="" BLUE="" YELLOW=""
fi

log()  { echo -e "  ${BLUE}●${RESET} $1"; }
ok()   { echo -e "  ${GREEN}✓${RESET} $1"; }
warn() { echo -e "  ${YELLOW}⚠${RESET} $1"; }
sub()  { echo -e "    ${DIM}↳${RESET} $1"; }

echo -e "\n${BOLD}fedora-setup${RESET} ${DIM}— setup codecs & drivers${RESET}\n"

# Ensure sudo credentials are ready
sudo -v

# 1. Repositories
log "Enabling RPM Fusion..."
sudo dnf install -y \
  https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
  https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm > /dev/null 2>&1
ok "RPM Fusion active"

# 2. Codecs (Swap restricted FFmpeg + Group Upgrade)
log "Swapping to full FFmpeg & upgrading multimedia..."
sudo dnf swap -y ffmpeg-free ffmpeg --allowerasing > /dev/null 2>&1
sudo dnf group upgrade --with-optional -y multimedia > /dev/null 2>&1
ok "Full FFmpeg & multimedia codecs ready"

# 3. Hardware Acceleration
log "Configuring hardware acceleration..."

# NVIDIA
if lspci | grep -qi nvidia; then
    sub "Detected: NVIDIA GPU"
    sudo dnf install -y akmod-nvidia xorg-x11-drv-nvidia-cuda kmodtool > /dev/null 2>&1

    sub "Building kernel module via akmods (this may take ~1-2 min)..."
    if sudo akmods --force > /dev/null 2>&1; then
        ok "NVIDIA kernel module built successfully"
    else
        warn "akmods build encountered an issue (check /var/log/akmods/akmods.log)"
    fi

    # Secure Boot Check & Guidance
    if mokutil --sb-state 2>/dev/null | grep -qi "enabled"; then
        if [ -f /etc/pki/akmods/certs/public_key.der ] && sudo mokutil --test-key /etc/pki/akmods/certs/public_key.der 2>&1 | grep -qi "already enrolled"; then
            ok "Secure Boot: MOK key already enrolled"
        else
            echo -e "\n    ${YELLOW}${BOLD}Secure Boot Action Required:${RESET}"
            echo -e "    ${DIM}To allow NVIDIA drivers to load with Secure Boot, enroll the MOK key:${RESET}"
            echo -e "    ${BOLD}sudo mokutil --import /etc/pki/akmods/certs/public_key.der${RESET}"
            echo -e "    ${DIM}1. Create a temporary password when prompted.${RESET}"
            echo -e "    ${DIM}2. Reboot your PC (the blue 'MOKManagement' screen will show).${RESET}"
            echo -e "    ${DIM}3. Select: Enroll MOK ➔ Continue ➔ Yes ➔ Enter password.${RESET}\n"
        fi
    fi
fi

# AMD
if lspci | grep -qi -E "vga.*amd|display.*amd|vga.*ati|display.*ati"; then
    sub "Detected: AMD GPU"
    sudo dnf swap -y mesa-va-drivers mesa-va-drivers-freeworld > /dev/null 2>&1 || true
    sudo dnf swap -y mesa-vdpau-drivers mesa-vdpau-drivers-freeworld > /dev/null 2>&1 || true
    ok "AMD freeworld video drivers installed"
fi

# Intel
if lspci | grep -qi -E "vga.*intel|display.*intel"; then
    sub "Detected: Intel GPU"
    sudo dnf install -y intel-media-driver libva-intel-driver > /dev/null 2>&1
    ok "Intel QuickSync media drivers installed"
fi

# --- Done ---
echo -e "\n${GREEN}${BOLD}✓ Setup complete.${RESET} ${DIM}Reboot your system to apply.${RESET}\n"
