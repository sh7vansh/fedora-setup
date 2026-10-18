# fedora-setup

Codecs and GPU drivers for mutable Fedora Workstation with DNF5.

### Run

```bash
curl -fsSL https://raw.githubusercontent.com/sh7vansh/fedora-setup/main/fedora-setup.sh | bash
```

Enables RPM Fusion, installs full FFmpeg and multimedia packages, and detects
NVIDIA, AMD, or Intel GPUs to install drivers. Stops on package installation errors.

### NVIDIA setup

1. The script opens the NVIDIA driver page in **Software** and exits.
2. If **Enable…** appears, click it and follow Software's instructions for Secure
   Boot and MOK enrollment.
3. Let driver installation finish, then reboot as directed.
4. Once Fedora starts, run `nvidia-smi` to check the driver.
