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

normalize_hex() { tr -d '[:space:]:' | tr '[:lower:]' '[:upper:]'; }

gpu_devices_for_vendor() {
    # Numeric display class and vendor IDs do not depend on pci.ids vendor names.
    grep -iE "\\[03[[:xdigit:]]{2}\\]:.*\\[$1:[[:xdigit:]]{4}\\]" <<< "$gpu_info"
}

nvidia_modules_match_key() {
    local module module_key
    for module in nvidia nvidia_modeset nvidia_drm nvidia_uvm; do
        module_key=$(modinfo -k "$target_kernel" -F sig_key "$module" 2>/dev/null) || return 1
        module_key=$(printf '%s' "$module_key" | normalize_hex)
        [[ -n "$module_key" && "$module_key" == "$signing_key_id" ]] || return 1
    done
}

trap 'warn "Setup failed at line ${LINENO}; see the error above." >&2' ERR
needs_mok_enrollment=false
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
    sudo dnf install -y ffmpeg
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
    target_kernel=$(uname -r)
    # akmods dependencies may only pull development files for a newer kernel.
    # Resolve the exact kernel capability (also covers Fedora kernel variants).
    if ! sudo dnf install -y "kernel-devel-uname-r = $target_kernel"; then
        die "Cannot install development files for $target_kernel. Update Fedora, reboot into the updated kernel, then rerun setup."
    fi
    sudo dnf install -y kmodtool akmods mokutil openssl
    # Respect the same signing configuration as kmodtool, including overrides.
    signing_cert=$(rpm --eval '%{__kmodtool_signmodules_pubkey}')
    signing_private_key=$(rpm --eval '%{__kmodtool_signmodules_privkey}')
    signing_enabled=$(rpm --eval '%{__kmodtool_signmodules}')
    [[ "$signing_enabled" == 1 ]] || die "Module signing is disabled in the kmodtool configuration."
    if ! sudo test -f "$signing_cert" || ! sudo test -f "$signing_private_key"; then
        [[ "$signing_cert" == /etc/pki/akmods/certs/public_key.der &&
           "$signing_private_key" == /etc/pki/akmods/private/private_key.priv ]] ||
            die "Configured signing key files are missing; repair the kmodtool configuration first."
        sudo kmodgenca -a
    fi
    # Validate both files and compare their public keys without printing private data.
    cert_public_key=$(sudo openssl x509 -inform DER -in "$signing_cert" -pubkey -noout)
    private_public_key=$(sudo openssl pkey -in "$signing_private_key" -passin pass: -pubout)
    [[ "$cert_public_key" == "$private_public_key" ]] || die "The signing certificate and private key do not match."
    signing_key_id=$(sudo openssl x509 -inform DER -in "$signing_cert" -noout -ext subjectKeyIdentifier |
        sed '1d' | normalize_hex)
    [[ "$signing_key_id" =~ ^[0-9A-F]+$ ]] || die "The signing certificate has no usable subject key identifier."
    sudo dnf install -y akmod-nvidia xorg-x11-drv-nvidia-cuda

    sub "Building NVIDIA modules (this may take several minutes)..."
    sudo akmods --force --akmod nvidia
    if ! nvidia_modules_match_key; then
        sub "Rebuilding modules for $target_kernel with the configured signing key..."
        sudo akmods --force --rebuild --akmod nvidia --kernels "$target_kernel"
    fi
    nvidia_modules_match_key || die "NVIDIA modules are missing or signed with a different key; check /var/log/akmods/akmods.log."
    nvidia_installed=true
    ok "NVIDIA modules for $target_kernel match the signing certificate"

    # Secure Boot Check & Guidance
    if [ -d /sys/firmware/efi ]; then
        secure_boot_state=$(LC_ALL=C mokutil --sb-state)
    else
        secure_boot_state="Legacy BIOS"
    fi
    if grep -qi "enabled" <<< "$secure_boot_state"; then
        cert_fingerprint=$(sudo openssl x509 -inform DER -in "$signing_cert" -noout -sha1 -fingerprint)
        cert_fingerprint=$(printf '%s' "${cert_fingerprint#*=}" | normalize_hex)
        [[ "$cert_fingerprint" =~ ^[0-9A-F]{40}$ ]] || die "Cannot read the signing certificate fingerprint."
        # Query failures must stop setup, rather than look like missing enrollment.
        enrolled_keys=$(LC_ALL=C sudo mokutil --list-enrolled)
        enrolled_keys=$(printf '%s' "$enrolled_keys" | normalize_hex)
        if [[ "$enrolled_keys" == *"$cert_fingerprint"* ]]; then
            ok "Secure Boot: MOK key already enrolled"
        else
            needs_mok_enrollment=true
            pending_keys=$(LC_ALL=C sudo mokutil --list-new)
            pending_keys=$(printf '%s' "$pending_keys" | normalize_hex)
            if [[ "$pending_keys" == *"$cert_fingerprint"* ]]; then
                sub "MOK enrollment is already queued; use the password set during import after reboot."
            else
                sub "Choose a temporary MOK password now; enter it again after reboot."
                sub "This password authorizes enrollment; it is separate from your sudo password."
                # Read from the terminal even when launched through curl | bash.
                if ! (exec </dev/tty) 2>/dev/null; then
                    warn "No interactive terminal; MOK enrollment has not been queued."
                    printf '      Run: sudo mokutil --import %q\n' "$signing_cert"
                    exit 1
                fi
                sudo mokutil --import "$signing_cert" </dev/tty
                pending_keys=$(LC_ALL=C sudo mokutil --list-new)
                pending_keys=$(printf '%s' "$pending_keys" | normalize_hex)
                [[ "$pending_keys" == *"$cert_fingerprint"* ]] || die "The signing key was not queued for enrollment."
                ok "MOK enrollment queued"
            fi
        fi
    fi
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
if "$needs_mok_enrollment"; then
    warn "Packages installed; NVIDIA still requires MOK enrollment."
    sub "Reboot to finish the queued enrollment."
    sub "Choose 'Enroll MOK' and enter the password you set during import."
else
    echo -e "\n${GREEN}${BOLD}✓ Setup complete.${RESET} ${DIM}Reboot your system to apply.${RESET}\n"
fi
if "$nvidia_installed"; then
    sub "After reboot, run nvidia-smi to verify the running NVIDIA driver."
fi
