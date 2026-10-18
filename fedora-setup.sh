#!/usr/bin/env bash
set -Eeuo pipefail

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
die()  { warn "$1" >&2; exit 1; }

gpu_devices_for_vendor() {
    # Numeric display class and vendor IDs do not depend on pci.ids vendor names.
    grep -iE "\\[03[[:xdigit:]]{2}\\]:.*\\[$1:[[:xdigit:]]{4}\\]" <<< "$gpu_info"
}

trap 'warn "Setup failed at line ${LINENO}; see the error above." >&2' ERR
nvidia_installed=false

echo -e "\n${BOLD}fedora-setup${RESET} ${DIM}— setup codecs & drivers${RESET}\n"

# Ensure sudo credentials are ready and keep them refreshed in the background
sudo -v
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
sudo_keepalive_pid=$!
trap 'kill "$sudo_keepalive_pid" 2>/dev/null || true' EXIT

# 1. Repositories
log "Enabling RPM Fusion..."
sudo dnf install -y \
  https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
  https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
ok "RPM Fusion active"

# 2. Codecs (Swap restricted FFmpeg + install missing group packages)
log "Installing full FFmpeg & multimedia..."
if rpm -q ffmpeg-free >/dev/null 2>&1; then
    sudo dnf swap -y ffmpeg-free ffmpeg --allowerasing
else
    # Fedora's libav*-free libraries can exist without the ffmpeg-free CLI.
    sudo dnf install -y ffmpeg --allowerasing
fi
sudo dnf group install --with-optional -y multimedia
ok "Full FFmpeg & multimedia codecs ready"

# 3. Hardware Acceleration
log "Configuring hardware acceleration..."
if ! command -v lspci >/dev/null 2>&1; then
    sudo dnf install -y pciutils
fi
# Capture once so grep's early exit cannot cause SIGPIPE with pipefail.
gpu_info=$(LC_ALL=C lspci -Dnn)

# NVIDIA
if nvidia_gpus=$(gpu_devices_for_vendor 10de); then
    sub "Detected: NVIDIA GPU"
    # Current drivers require Turing or newer. Fail closed when the local
    # pci.ids database cannot identify a known supported architecture, too.
    # Check every GPU: a supported card must not hide an older second card.
    while IFS= read -r gpu; do
        if ! grep -qE '[[:space:]](TU|GA|AD|GH|GB)[0-9]{3}[[:alnum:]]*([[:space:]]|$)' <<< "$gpu"; then
            warn "Cannot confirm current NVIDIA driver support for: $gpu"
            die "NVIDIA driver installation stopped. Older GPUs need a compatible legacy branch; check https://rpmfusion.org/Howto/NVIDIA. For an unrecognized GPU, update pci.ids and verify driver support first."
        fi
    done <<< "$nvidia_gpus"
    sudo dnf install -y akmod-nvidia xorg-x11-drv-nvidia-cuda
    nvidia_installed=true
    ok "NVIDIA driver packages installed"
fi

# AMD
if gpu_devices_for_vendor 1002 >/dev/null; then
    sub "Detected: AMD GPU"
    if rpm -q mesa-va-drivers-freeworld >/dev/null 2>&1; then
        sudo dnf install -y mesa-va-drivers-freeworld
    elif rpm -q mesa-va-drivers >/dev/null 2>&1; then
        sudo dnf swap -y mesa-va-drivers mesa-va-drivers-freeworld
    else
        sudo dnf install -y mesa-va-drivers-freeworld
    fi
    ok "AMD freeworld video drivers installed"
fi

# Intel
if gpu_devices_for_vendor 8086 >/dev/null; then
    sub "Detected: Intel GPU"
    sudo dnf install -y intel-media-driver libva-intel-driver
    ok "Intel QuickSync media drivers installed"
fi

# --- Done ---
echo -e "\n${GREEN}${BOLD}✓ Setup complete.${RESET}\n"
if "$nvidia_installed"; then
    sub "Opening the NVIDIA driver page in Software..."
    sub "If an 'Enable…' button appears, click it and follow the setup instructions."
    command -v gnome-software >/dev/null 2>&1 ||
        die "Software is unavailable; open your software manager to finish NVIDIA setup."
    gnome-software --details=xorg-x11-drv-nvidia </dev/null &
    exit 0
else
    sub "Reboot your system to apply."
fi
