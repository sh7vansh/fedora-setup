# fedora-setup

Minimal, conflict-free post-install script for fresh Fedora Workstation installs.

### Run

```bash
curl -fsSL https://raw.githubusercontent.com/sh7vansh/fedora-setup/main/fedora-setup.sh | bash
```

### What it does

- Enables **RPM Fusion** (free & non-free)
- Replaces restricted `ffmpeg-free` with full **FFmpeg** (`--allowerasing`)
- Upgrades **`@multimedia`** group (GStreamer plugins, aptX Bluetooth audio)
- Auto-detects GPU and configures hardware acceleration:
  - **NVIDIA:** `akmod-nvidia` + CUDA (verifies akmods build & checks Secure Boot)
  - **AMD:** `mesa-va-drivers-freeworld`
  - **Intel:** `intel-media-driver` (QuickSync)
