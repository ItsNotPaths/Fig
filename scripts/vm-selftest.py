"""Drive the tildesh live image over its serial port.

The kernel and the initramfs are taken out of the ISO and handed to QEMU
directly. That skips GRUB, whose menu has no timeout and no serial terminal,
and it lets the kernel put its own log on ttyS0 as well.

QEMU puts the guest's ttyS0 on a unix socket. The image runs agetty there, so
this logs in the same way a person would, runs one command, and reads what
comes back.
"""
import os
import re
import socket
import subprocess
import sys
import tempfile
import time

ANSI = re.compile(r"\x1b\[[0-9;?]*[a-zA-Z]|\x1b[()][B0]|[\x0e\x0f\r]")

USER = "tildesh"
PASSWORD = "tildesh"
BOOT_TIMEOUT = 180
CMD_TIMEOUT = 120


class Serial:
    """The guest's ttyS0. Everything read is also written to `log`, so a run
    that goes wrong leaves the whole console behind."""

    def __init__(self, path, log):
        self.log = open(log, "w")
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        for _ in range(100):
            try:
                self.sock.connect(path)
                break
            except (FileNotFoundError, ConnectionRefusedError):
                time.sleep(0.1)
        else:
            raise SystemExit("vm-selftest: qemu never opened the serial socket")
        self.sock.settimeout(0.5)
        self.raw = ""

    @property
    def buf(self):
        """What was read, with the colours and the cursor moves taken out.
        Stripping the whole buffer rather than each chunk matters: an escape
        sequence split across two reads would survive a per-chunk strip and
        glue itself to the front of the next line."""
        return ANSI.sub("", self.raw)

    def expect(self, pattern, timeout):
        """Read until the pattern matches, and return everything read."""
        deadline = time.monotonic() + timeout
        rx = re.compile(pattern)
        while time.monotonic() < deadline:
            if rx.search(self.buf):
                return self.buf
            try:
                data = self.sock.recv(4096)
            except socket.timeout:
                continue
            if not data:
                raise EOFError("the guest closed its console")
            text = data.decode("utf-8", "replace")
            self.log.write(text)
            self.log.flush()
            self.raw += text
        raise TimeoutError(f"no match for {pattern!r}")

    def send(self, line):
        self.raw = ""
        self.sock.sendall((line + "\n").encode())


def unpack(iso, tmp):
    """Pull the kernel, the initramfs and the volume label out of the image."""
    subprocess.run(
        ["bsdtar", "xf", iso, "-C", tmp,
         "boot/vmlinuz-x86_64", "boot/initramfs-x86_64.img", "boot/grub/kernels.cfg"],
        check=True)
    cfg = open(os.path.join(tmp, "boot/grub/kernels.cfg")).read()
    label = re.search(r"label=(\S+)", cfg)
    if not label:
        raise SystemExit("vm-selftest: no volume label in the image's kernels.cfg")
    return (os.path.join(tmp, "boot/vmlinuz-x86_64"),
            os.path.join(tmp, "boot/initramfs-x86_64.img"),
            label.group(1))


def main(iso):
    tmp = tempfile.mkdtemp(prefix="tildesh-vm-")
    sock_path = os.path.join(tmp, "console")
    kernel, initrd, label = unpack(iso, tmp)

    qemu = subprocess.Popen([
        "qemu-system-x86_64",
        "-machine", "q35,accel=kvm", "-cpu", "host", "-smp", "4", "-m", "4G",
        "-kernel", kernel, "-initrd", initrd,
        # The same arguments GRUB's defaults.cfg passes. Booting the kernel
        # directly skips GRUB, and without these the live init composes
        # LANG=.UTF-8 from an empty lang=, which breaks the locale in a way
        # no real boot does.
        "-append", f"lang=en_US keytable=us tz=UTC "
                   f"label={label} overlay=livefs console=ttyS0,115200",
        "-cdrom", iso,
        "-device", "VGA", "-display", "none",
        "-serial", f"unix:{sock_path},server,nowait",
        "-nic", "user,model=virtio-net-pci",
    ], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)

    console = os.path.join(os.path.dirname(iso), "console.log")
    status = 1
    try:
        con = Serial(sock_path, console)
        print("==> waiting for the login prompt")
        con.expect(r"login:", BOOT_TIMEOUT)

        con.send(USER)
        con.expect(r"[Pp]assword:", 30)
        con.send(PASSWORD)
        con.expect(r"\]\$", 120)
        print("==> logged in")

        # The marker is how we know the command finished, whatever it printed.
        con.send("tildesh-selftest; echo SELFTEST_RC=$?")
        out = con.expect(r"SELFTEST_RC=\d+", CMD_TIMEOUT)

        for line in out.splitlines():
            if line.startswith(("ok\t", "not ok\t", "skip\t")):
                print(line)
        rc = int(re.search(r"SELFTEST_RC=(\d+)", out).group(1))
        print(f"==> {rc} failures")
        status = rc

        con.send("poweroff")
        time.sleep(3)
    except (TimeoutError, EOFError, SystemExit) as e:
        print(f"==> {e}", file=sys.stderr)
        print(f"==> console: {console}", file=sys.stderr)
        if qemu.poll() is not None:
            print(f"==> qemu exited {qemu.returncode}: "
                  f"{qemu.stderr.read().decode(errors='replace')[-500:]}", file=sys.stderr)
    finally:
        qemu.terminate()
        try:
            qemu.wait(timeout=10)
        except subprocess.TimeoutExpired:
            qemu.kill()
    return status


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
