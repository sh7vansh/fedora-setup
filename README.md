# fedora-setup

A minimal, conflict-free post-install script for fresh Fedora Workstation installs.

It equips stock Fedora with the essentials that can't ship out-of-the-box due to patent and legal constraints, without bloating or modifying your desktop:

- **RPM Fusion** (free and non-free)
- **Full FFmpeg** (cleanly swapped with `--allowerasing` to replace restricted `ffmpeg-free`)
- **Multimedia Codecs** (`@multimedia` group with optional plugins and aptX Bluetooth audio)
- **Automatic GPU Detection & Acceleration**:
  - **NVIDIA:** Installs `akmod-nvidia` and CUDA, compiles kernel modules
  - **AMD:** Swaps to `mesa-va-drivers-freeworld` for full hardware video decode
  - **Intel:** Installs `intel-media-driver` for QuickSync hardware acceleration

---

## Usage

### Quick Run (via curl)
```bash
curl -fsSL https://raw.githubusercontent.com/<username>/fedora-setup/main/fedora-setup.sh | bash
```

### Local Run
```bash
git clone https://github.com/<username>/fedora-setup.git
cd fedora-setup
./fedora-setup.sh
```

---

## What It Does Under the Hood

```bash
# 1. Enable RPM Fusion
sudo dnf install -y https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
                    https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm

# 2. Swap restricted FFmpeg & upgrade multimedia group
sudo dnf swap -y ffmpeg-free ffmpeg --allowerasing
sudo dnf group upgrade --with-optional -y multimedia

# 3. Auto-detect GPU and configure hardware decoders
# - NVIDIA: akmod-nvidia, xorg-x11-drv-nvidia-cuda, akmods --force
# - AMD:    mesa-va-drivers-freeworld, mesa-vdpau-drivers-freeworld
# - Intel:  intel-media-driver, libva-intel-driver
```

## License
MIT
