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

Use an interactive terminal. If enrollment is needed, choose a temporary password
at the `mokutil` prompt (typed characters stay hidden). Reboot, select
**Enroll MOK → Continue → Yes**, enter that password, and reboot again.
Existing keys and pending enrollment requests are reused. After reboot, check
the driver with `nvidia-smi`.

### Checks

```bash
bash -n fedora-setup.sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -v
```

Tests require Python 3 and OpenSSL; system-changing commands are mocked.
