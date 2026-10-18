# fedora-setup

Post-install script for mutable Fedora Workstation installs using DNF5.

### Run

```bash
curl -fsSL https://raw.githubusercontent.com/sh7vansh/fedora-setup/main/fedora-setup.sh | bash
```

### What it does

- Enables **RPM Fusion** (free & non-free)
- Replaces restricted `ffmpeg-free` with full **FFmpeg** (`--allowerasing`)
- Installs **`@multimedia`** including optional packages using DNF5
- Auto-detects GPU and configures hardware acceleration:
  - **NVIDIA:** `akmod-nvidia` + CUDA (verifies akmods build & checks Secure Boot)
  - **AMD:** `mesa-va-drivers-freeworld`
  - **Intel:** `intel-media-driver` (QuickSync)

Package-manager output stays visible, and installation or NVIDIA build failures
stop the script. NVIDIA modules for the running kernel are checked against the
configured signing certificate and rebuilt if needed. Existing signing keys are
preserved; invalid or mismatched key files stop setup.

With Secure Boot enabled, the script checks enrolled and pending keys separately.
If enrollment is needed, `mokutil` prompts you to choose and confirm a temporary
password. On reboot, choose **Enroll MOK → Continue → Yes**, enter that password,
and reboot again. A pending request is reused without another import or password
prompt. Enrollment requires an interactive terminal, including when using
`curl | bash`; without one, setup stops and prints the manual import command.

After reboot, run `nvidia-smi` to verify the running NVIDIA driver. A successful
build verifies the installed module's signing key, not that the running driver
has already switched to the newly installed version.

### Check without installing packages

```bash
bash -n fedora-setup.sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -v
```

The tests use disposable certificates and mocked package, driver, and enrollment
commands. They require Python 3 and OpenSSL and make no system configuration changes.
