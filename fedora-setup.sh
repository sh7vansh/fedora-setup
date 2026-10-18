#!/usr/bin/env bash
set -euo pipefail

# --- Colors & Symbols ---
if [ -t 1 ]; then
    BOLD="\033[1m"
    DIM="\033[2m"
    RESET="\033[0m"
    GREEN="\033[32m"
    BLUE="\033[34m"
else
    BOLD="" DIM="" RESET="" GREEN="" BLUE=""
fi

log() { echo -e "  ${BLUE}●${RESET} $1"; }
ok()  { echo -e "  ${GREEN}✓${RESET} $1"; }
sub() { echo -e "    ${DIM}↳${RESET} $1"; }

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
    sudo dnf install -y akmod-nvidia xorg-x11-drv-nvidia-cuda > /dev/null 2>&1
    sub "Building kernel module..."
    sudo akmods --force > /dev/null 2>&1
    ok "NVIDIA akmod installed"
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
