"""Run the installer with mocked system commands; never modify the host."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "fedora-setup.sh"
MOCKS = r'''
sudo() {
    printf '%s\n' "$*" >> "$SETUP_TEST_LOG"
    case "$1" in
        -v|test|akmods) return 0 ;;
        dnf)
            if [[ "$*" == *"kernel-devel-uname-r = "* ]]; then
                return "${SETUP_TEST_DEVEL_FAILURE:-0}"
            fi
            return 0 ;;
        openssl) shift; openssl "$@" ;;
        *) printf 'Unexpected sudo command: %s\n' "$*" >&2; return 99 ;;
    esac
}
lspci() { printf '%s\n' "$SETUP_TEST_GPUS"; }
uname() { printf 'test-kernel\n'; }
rpm() {
    case "$*" in
        '-E %fedora') printf '44\n' ;;
        '--eval %{__kmodtool_signmodules_pubkey}') printf '/mock/cert.der\n' ;;
        '--eval %{__kmodtool_signmodules_privkey}') printf '/mock/key.priv\n' ;;
        '--eval %{__kmodtool_signmodules}') printf '1\n' ;;
        '-q '*) return 1 ;;
        *) return 99 ;;
    esac
}
openssl() {
    case "$*" in
        *subjectKeyIdentifier*) printf 'X509v3 Subject Key Identifier:\n    AA:BB\n' ;;
        *) printf 'mock-public-key\n' ;;
    esac
}
modinfo() { printf 'AA:BB\n'; }
mokutil() { printf 'SecureBoot disabled\n'; }
'''


def gpu(vendor, name, device="1234", pci_class="0300"):
    return (
        f"0000:01:00.0 VGA compatible controller [{pci_class}]: "
        f"{name} [{vendor}:{device}] (rev a1)"
    )


class SetupTests(unittest.TestCase):
    def run_setup(self, *gpus, devel_failure=False):
        with tempfile.TemporaryDirectory() as directory:
            mocks = Path(directory) / "mocks.sh"
            log = Path(directory) / "commands.log"
            mocks.write_text(MOCKS)
            env = {
                **os.environ,
                "BASH_ENV": str(mocks),
                "SETUP_TEST_LOG": str(log),
                "SETUP_TEST_GPUS": "\n".join(gpus),
                "SETUP_TEST_DEVEL_FAILURE": str(int(devel_failure)),
            }
            result = subprocess.run(
                ["bash", str(SCRIPT)], env=env, text=True,
                capture_output=True, timeout=10,
            )
            return result, log.read_text().splitlines()

    def test_vendor_routing(self):
        cases = [
            (gpu("10de", "NVIDIA Corporation GA107M"), True, False, False),
            (gpu("8086", "Intel Corporation UHD Graphics 620"), False, False, True),
            (gpu("1002", "Advanced Micro Devices, Inc. [AMD/ATI] Cezanne"), False, True, False),
            (gpu("1002", "Unknown vendor"), False, True, False),
            (gpu("1002", "AMD audio controller", pci_class="0403"), False, False, False),
        ]
        for device, nvidia, amd, intel in cases:
            with self.subTest(device=device):
                result, commands = self.run_setup(device)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(any("install -y akmod-nvidia " in c for c in commands), nvidia)
                self.assertEqual(any("mesa-va-drivers-freeworld" in c for c in commands), amd)
                self.assertEqual(any("intel-media-driver" in c for c in commands), intel)

    def test_supported_nvidia_architectures(self):
        for chip in ("TU117", "GA107M", "AD107", "GH100", "GB202"):
            with self.subTest(chip=chip):
                result, commands = self.run_setup(gpu("10de", f"NVIDIA Corporation {chip}"))
                self.assertEqual(result.returncode, 0, result.stderr)
                devel = commands.index("dnf install -y kernel-devel-uname-r = test-kernel")
                driver = commands.index("dnf install -y akmod-nvidia xorg-x11-drv-nvidia-cuda")
                self.assertLess(devel, driver)

    def test_legacy_unknown_and_mixed_nvidia_cards_stop_before_driver_install(self):
        for chip in ("GK208", "GM107", "GP107M", "GV100", "Device 9999"):
            for mixed in (False, True):
                with self.subTest(chip=chip, mixed=mixed):
                    devices = [gpu("10de", f"NVIDIA Corporation {chip}")]
                    if mixed:
                        devices.insert(0, gpu("10de", "NVIDIA Corporation GA107M"))
                    result, commands = self.run_setup(*devices)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn("NVIDIA driver installation stopped", result.stderr)
                    self.assertFalse(any("akmod-nvidia" in c for c in commands))
                    self.assertFalse(any("akmods" in c for c in commands))

    def test_missing_running_kernel_devel_stops_with_recovery_guidance(self):
        result, commands = self.run_setup(
            gpu("10de", "NVIDIA Corporation GA107M"), devel_failure=True,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("reboot into the updated kernel", result.stderr)
        self.assertFalse(any("akmod-nvidia" in c for c in commands))

    def test_hybrid_system_installs_both_vendors(self):
        result, commands = self.run_setup(
            gpu("10de", "NVIDIA Corporation GA107M", pci_class="0302"),
            gpu("1002", "Advanced Micro Devices, Inc. [AMD/ATI] Cezanne"),
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(any("akmod-nvidia" in c for c in commands))
        self.assertTrue(any("mesa-va-drivers-freeworld" in c for c in commands))


if __name__ == "__main__":
    unittest.main()
