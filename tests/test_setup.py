"""Exercise setup with disposable keys and mocked system-changing commands."""

import fcntl
import os
from pathlib import Path
import pty
import subprocess
import tempfile
import termios
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "fedora-setup.sh"
MOCK = r'''#!/usr/bin/env bash
set -eu
printf '%s %s\n' "${0##*/}" "$*" >> "$MOCK_ROOT/commands"
case "${0##*/}" in
sudo)
    [[ $1 == -v ]] && exit 0
    exec "$@"
    ;;
rpm)
    if [[ $1 == --eval ]]; then
        case "$2" in
            *pubkey*) echo "$MOCK_ROOT/cert.der" ;;
            *privkey*) echo "$MOCK_ROOT/key.pem" ;;
            *) echo 1 ;;
        esac
    elif [[ $1 == -E ]]; then
        echo 44
    else
        exit 1
    fi
    ;;
dnf)
    [[ $MOCK_SCENARIO != dnf-failure ]] || exit 1
    ;;
lspci)
    echo '01:00.0 VGA compatible controller: NVIDIA Corporation RTX 3050'
    echo '06:00.0 VGA compatible controller: Advanced Micro Devices [AMD/ATI]'
    ;;
akmods)
    [[ $MOCK_SCENARIO != build-failure ]] || exit 1
    if [[ " $* " == *' --rebuild '* ]]; then touch "$MOCK_ROOT/rebuilt"; fi
    ;;
modinfo)
    if [[ $MOCK_SCENARIO == bad-signature ]] ||
       { [[ $MOCK_SCENARIO == stale-signature ]] && [[ ! -e $MOCK_ROOT/rebuilt ]]; }; then
        echo 'DE:AD:BE:EF'
    else
        echo "$MOCK_KEY_ID"
    fi
    ;;
mokutil)
    case "$1" in
        --sb-state)
            if [[ $MOCK_SCENARIO == disabled ]]; then echo 'SecureBoot disabled';
            else echo 'SecureBoot enabled'; fi
            ;;
        --list-enrolled)
            [[ $MOCK_SCENARIO != query-failure ]] || exit 255
            if [[ $MOCK_SCENARIO == enrolled ]]; then echo "SHA1 Fingerprint: $MOCK_FINGERPRINT"; fi
            ;;
        --list-new)
            if [[ $MOCK_SCENARIO == pending || -e $MOCK_ROOT/imported ]]; then
                echo "SHA1 Fingerprint: $MOCK_FINGERPRINT"
            fi
            ;;
        --import)
            read -r first
            read -r second
            [[ $first == test-password && $first == "$second" ]] || exit 1
            [[ $MOCK_SCENARIO != import-failure ]] || exit 1
            if [[ $MOCK_SCENARIO != import-not-queued ]]; then touch "$MOCK_ROOT/imported"; fi
            ;;
        *) exit 2 ;;
    esac
    ;;
*) exit 2 ;;
esac
'''


class SetupTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="fedora-setup-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        for name in ("sudo", "rpm", "dnf", "lspci", "akmods", "modinfo", "mokutil"):
            executable = self.bin / name
            executable.write_text(MOCK)
            executable.chmod(0o755)
        # Override only the firmware-directory probe, leaving real file tests intact.
        bash_env = self.root / "bash-env"
        bash_env.write_text('''[() {
    if [[ $# == 3 && $1 == -d && $2 == /sys/firmware/efi ]]; then
        [[ $MOCK_SCENARIO != legacy ]]
    else
        builtin [ "$@"
    fi
}
''')
        self.openssl("req", "-x509", "-newkey", "rsa:2048", "-nodes",
                     "-keyout", str(self.root / "key.pem"), "-outform", "DER",
                     "-out", str(self.root / "cert.der"), "-subj", "/CN=setup-test",
                     "-days", "1", "-addext", "subjectKeyIdentifier=hash")
        fingerprint = self.openssl("x509", "-inform", "DER", "-in",
                                   str(self.root / "cert.der"), "-noout",
                                   "-sha1", "-fingerprint").split("=", 1)[1].strip()
        key_id = self.openssl("x509", "-inform", "DER", "-in",
                              str(self.root / "cert.der"), "-noout", "-ext",
                              "subjectKeyIdentifier").splitlines()[1].strip()
        self.env = dict(os.environ, PATH=f"{self.bin}:/usr/bin:/bin",
                        BASH_ENV=str(bash_env), MOCK_ROOT=str(self.root),
                        MOCK_FINGERPRINT=fingerprint, MOCK_KEY_ID=key_id)

    def openssl(self, *args):
        return subprocess.run(["openssl", *args], check=True, text=True,
                              capture_output=True).stdout

    def run_setup(self, scenario, terminal=False):
        env = dict(self.env, MOCK_SCENARIO=scenario)
        if terminal:
            master, slave = pty.openpty()
            self.addCleanup(os.close, master)
            self.addCleanup(os.close, slave)

            def attach_terminal():
                os.setsid()
                fcntl.ioctl(slave, termios.TIOCSCTTY, 0)

            with subprocess.Popen(["bash", str(SCRIPT)], env=env, stdin=slave,
                                  stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                  text=True, preexec_fn=attach_terminal) as proc:
                os.write(master, b"test-password\ntest-password\n")
                output, _ = proc.communicate(timeout=20)
                code = proc.returncode
        else:
            proc = subprocess.run(["bash", str(SCRIPT)], env=env,
                                  start_new_session=True, text=True,
                                  capture_output=True, timeout=20)
            output = proc.stdout + proc.stderr
            code = proc.returncode
        commands = (self.root / "commands").read_text()
        return code, output, commands

    def test_existing_enrollment_needs_no_import_or_rebuild(self):
        code, output, commands = self.run_setup("enrolled")
        self.assertEqual(code, 0, output)
        self.assertIn("MOK key already enrolled", output)
        self.assertNotIn("mokutil --import", commands)
        self.assertNotIn("--rebuild", commands)

    def test_pending_request_is_reused_without_terminal(self):
        code, output, commands = self.run_setup("pending")
        self.assertEqual(code, 0, output)
        self.assertIn("enrollment is already queued", output)
        self.assertNotIn("MOK key already enrolled", output)
        self.assertNotIn("mokutil --import", commands)

    def test_new_enrollment_reads_password_from_terminal(self):
        code, output, commands = self.run_setup("fresh", terminal=True)
        self.assertEqual(code, 0, output)
        self.assertIn("MOK enrollment queued", output)
        self.assertIn("mokutil --import", commands)
        self.assertNotIn("test-password", output)

    def test_stale_signature_triggers_rebuild(self):
        code, output, commands = self.run_setup("stale-signature", terminal=True)
        self.assertEqual(code, 0, output)
        self.assertIn("--rebuild --akmod nvidia --kernels", commands)

    def test_disabled_and_legacy_boot_need_no_import(self):
        for scenario in ("disabled", "legacy"):
            with self.subTest(scenario=scenario):
                code, output, commands = self.run_setup(scenario)
                self.assertEqual(code, 0, output)
                self.assertNotIn("mokutil --import", commands)

    def test_failures_never_report_success(self):
        for scenario in ("dnf-failure", "build-failure", "query-failure",
                         "bad-signature", "fresh", "import-failure", "import-not-queued"):
            with self.subTest(scenario=scenario):
                code, output, _ = self.run_setup(
                    scenario, terminal=scenario in ("import-failure", "import-not-queued"))
                self.assertNotEqual(code, 0, output)
                self.assertNotIn("Setup complete", output)
                self.assertNotIn("Packages installed;", output)

    def test_mismatched_key_pair_stops_before_driver_install(self):
        self.openssl("genpkey", "-algorithm", "RSA", "-pkeyopt", "rsa_keygen_bits:2048",
                     "-out", str(self.root / "key.pem"))
        code, output, commands = self.run_setup("enrolled")
        self.assertNotEqual(code, 0, output)
        self.assertIn("do not match", output)
        self.assertNotIn("dnf install -y akmod-nvidia", commands)


if __name__ == "__main__":
    unittest.main()
