# fedora-setup

Codecs and GPU drivers for mutable Fedora Workstation with DNF5.

### Run

```bash
curl -fsSL https://raw.githubusercontent.com/sh7vansh/fedora-setup/main/fedora-setup.sh | bash
```

Enables RPM Fusion, installs full FFmpeg and multimedia packages, and detects
NVIDIA, AMD, or Intel GPUs to install drivers. Checks NVIDIA signing keys,
rebuilds modules when needed, and stops on errors.

GPU vendors are detected by PCI ID. Automatic NVIDIA installation is limited
to recognized Turing, Ampere, Ada, Hopper, and Blackwell GPUs; older or
unrecognized GPUs stop setup before NVIDIA driver installation. Check
[RPM Fusion's NVIDIA guide](https://rpmfusion.org/Howto/NVIDIA) for a compatible
legacy driver, or update your PCI ID database if your newer GPU is unrecognized.
Every NVIDIA GPU must pass this check on systems with multiple cards.

Setup installs development files matching the running kernel before installing
NVIDIA drivers. If those files are unavailable, update Fedora, reboot into the
updated kernel, and rerun setup.

### NVIDIA Secure Boot

1. If prompted, choose a temporary password (typing stays hidden).
2. Reboot and select **Enroll MOK → Continue → Yes**.
3. Enter the same password, then reboot again.
4. Once Fedora starts, run `nvidia-smi` to check the driver.
