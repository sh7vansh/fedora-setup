# fedora-setup

Codecs and GPU drivers for mutable Fedora Workstation with DNF5.

### Run

```bash
curl -fsSL https://raw.githubusercontent.com/sh7vansh/fedora-setup/main/fedora-setup.sh | bash
```

Enables RPM Fusion, installs full FFmpeg and multimedia packages, and detects
NVIDIA, AMD, or Intel GPUs to install drivers. Checks NVIDIA signing keys,
rebuilds modules when needed, and stops on errors.

### NVIDIA Secure Boot

1. If prompted, choose a temporary password (typing stays hidden).
2. Reboot and select **Enroll MOK → Continue → Yes**.
3. Enter the same password, then reboot again.
4. Once Fedora starts, run `nvidia-smi` to check the driver.

### Checks

```bash
bash -n fedora-setup.sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -v
```

Tests require Python 3 and OpenSSL; system-changing commands are mocked.
