# tildesh

An Artix image that boots to a Wayland session and nothing else.

tildesh is a desktop made of three programs — a window manager (`hedl`, a dwl
fork), a shell (`kippsrv`) and a renderer (`wweft`) — that speak one line
protocol. This repo is the ground they stand on: the package list, the ISO,
and a self test that checks the image on the image.

The image is built inside a container, so the only thing a build host needs is
docker.

## Layout

```
docker/Dockerfile   the Artix build host
profile/
  common/           our package base. Replaces Artix's, which is Xorg-shaped
  tildesh/
    profile.yaml    the desktop, the services, the live user
    root-overlay/   files copied into the image
packaging/
  build-packages.sh build our packages, index them into repo/
  kippsrv/PKGBUILD  wraps a binary this machine built
  wweft/PKGBUILD    the same
  hedl-wm/PKGBUILD  compiles hedl in the container
scripts/
  build-host.sh     build the container image
  build-iso.sh      build the ISO into dist/
  vm.sh             boot the ISO in QEMU, with the radios if you want them
  vm-selftest.sh    boot it with nobody watching and run the self test
download-deps.sh    fetch vendor/. Reference trees only, nothing that ships
```

`docs/`, `vendor/`, `repo/` and `dist/` are gitignored. README.md is the only
document that ships.

## Where our files live

One rule: **nothing of ours goes in `/etc`.**

`/etc` is for machine facts that must exist before anyone logs in — `fstab`,
`passwd`, `resolv.conf`. A window manager's key table and a shell's source list
are not that, and putting them there splits one idea across two directories for
no reason but habit.

| Kind | Where | Example |
| --- | --- | --- |
| authored | `~/.config/<name>/` | `~/.config/hedl/hedl.lua` |
| runtime state | `$XDG_RUNTIME_DIR/<name>/` | `/run/user/1000/hedl/kipp` |
| durable state | `~/.local/state/<name>/` | |
| installed | `/usr/share/<name>/` | `/usr/share/kippsrv/lua/` |

The names come from the XDG base directory spec, which is the same split FHS
makes with `/etc`, `/var/lib`, `/var/cache` and `/usr/share` — with better
names, and without duplicating every category once per user and once per
machine. On a single-user system that duplication buys nothing.

`kippsrv.lua` used to live in `/etc/tildesh/`. It is the reason this rule is
written down.

## Build

```sh
./download-deps.sh
./packaging/build-packages.sh
./scripts/build-iso.sh
```

`build-packages.sh` builds from the sibling repos beside this one and indexes
the result into `repo/`. Override the locations with `KIPPSRV_DIR`,
`WWEFT_DIR` and `HEDL_DIR`.

kippsrv and wweft are built on this machine and not in the container: kippsrv
is Odin, which is in no Artix repo, and wweft's build wants protocol sources
it vendors itself. Artix and Arch carry the same glibc, and neither binary
links anything else that moves. `ldd` after a build is the check.

hedl is built in the container, because nothing stops it: it is C, and
`wlroots0.19` and the rest are Artix packages. Only its source is staged.

`buildiso` reads `repo/` as `file:///repo`, through a pacman config the
container derives from the one artools ships.

The first build downloads about 1 GB of packages and takes some minutes. The
pacman cache and the chroot copies live in docker volumes, so the second build
is much faster. Any argument is passed to `buildiso`; `-q` prints the settings
and builds nothing.

The image lands in `dist/tildesh/`.

## Run it

```sh
./scripts/vm.sh              # no radios
./scripts/vm.sh --bt         # plus the MT7925 bluetooth half, over USB
./scripts/vm.sh --wifi       # plus the MT7925 wifi card, over VFIO
./scripts/vm.sh --disk       # add a 32G disk for an installed system
./scripts/vm.sh --serial     # no window. A login on this terminal instead
```

The window needs one package Arch splits out:

```sh
pacman -S qemu-system-x86 qemu-ui-gtk edk2-ovmf qemu-hw-display-virtio-vga-gl
```

`--serial` needs none of it. The image runs a getty on ttyS0, so QEMU with
`-serial mon:stdio` is a whole test rig: log in, run the self test, read the
output, with no screen involved.

`scripts/vm-selftest.sh` is that rig with nobody driving it. It boots the
newest image with no window, logs in over the serial port, runs
`tildesh-selftest`, prints what it said and powers the machine off. Its exit
status is the number of failed checks, and the whole console is left in
`dist/*/console.log`.

`--wifi` gives the card to the guest and takes it from the host until QEMU
exits, so the script refuses to start while the host's own route goes over it.
Plug in ethernet first. `--bt` needs nothing: the bluetooth half is a plain USB
device and comes back on its own.

The live user is `tildesh`, the password is `tildesh`, and tty1 logs in and
starts sway on its own.

## Looking at kipp

The session starts `kippsrv ~/.config/kippsrv/kippsrv.lua`, which reads hedl,
NetworkManager, PipeWire, backlight, power and the tray, and publishes the lot
on one socket.

`test-wweft` puts everything on that socket on a wweft surface. Mod+d, or the
command. `q` quits, `c` clears, `r` hides the raw lines.

The panel names no kind. It splits a line the way `kipp`'s spec says to, which
is the kind first, then the subject fields, then the attributes from the first
field holding an `=`. A fact no adapter writes yet shows up the day one does.

It is also the answer to whether wweft can read kippsrv without new C:
`Surface.listen` on a path connects to that socket and hands each line to
`onMessage`. That was already there for compositor event sockets.

## The self test

`tildesh-selftest` is on the image, at `/usr/local/bin`. It starts sway on the
headless wlroots backend, so it needs no GPU, no seat and no monitor. Run it
over ssh, in the VM, or from tty2 while the desktop is up.

```
ok	sway-headless
ok	seed-get_outputs
ok	seed-get_workspaces
ok	stream-line-delimited
ok	stream-workspace-focus
skip	kippsrv-sway	kippsrv not installed
```

What it is for: kippsrv reads a window manager through one Lua adapter, and
the sway adapter assumes sway's event stream is one JSON object a line.
`stream-line-delimited` is that assumption, checked. If it ever fails, the
adapter needs sway's binary IPC instead, which costs an outbound request path
kippsrv does not have yet.

The same file runs in a container, which is the fast loop:

```sh
docker run --rm --cap-add=SYS_NICE \
    -v "$PWD/profile/tildesh/root-overlay/usr/local/bin/tildesh-selftest:/usr/local/bin/tildesh-selftest:ro" \
    artixlinux/artixlinux:base-devel sh -c '
        pacman -Sy --noconfirm --needed sway jq socat ttf-dejavu >/dev/null
        mkdir -p /run/user/0 && chmod 700 /run/user/0
        XDG_RUNTIME_DIR=/run/user/0 tildesh-selftest'
```

`--cap-add=SYS_NICE` is only for the container. Artix ships sway with
`cap_sys_nice`, and exec fails without it.

## What Artix decided for us

**The seat is elogind, not seatd.** `elogind-runit` and `seatd-runit` are
marked as conflicting, `base` depends on an `init-logind` that only elogind
provides, and polkit and the portals want the logind D-Bus API anyway.
`libseat` inside wlroots finds logind on its own.

**There is no user service manager.** runit has none, `turnstile` is packaged
for dinit and openrc but not for runit, and there is no `pipewire-runit`. So
the session starts its own daemons: `.bash_profile` execs `dbus-run-session
sway`, and the sway config execs pipewire, wireplumber and dunst.

**Some services enable themselves.** `dbus-runit`, `elogind-runit`,
`artix-live-runit` and `runit` all ship their own symlink in
`runsvdir/default`. Naming one of those in `profile.yaml` makes buildiso abort,
because its own `ln -s` fails on a link that already exists.

**elogind can be started twice, and then no one can log in.** runit supervises
it as `logind`, and D-Bus activates it for any client that asks for
`org.freedesktop.login1`. Whichever wins the race owns the name; the loser
prints "elogind is already running" and exits. When D-Bus wins, runsv restarts
its copy once a second forever and a login blocks in `pam_elogind`. Artix
normally wins the race and never sees it. The overlay replaces the D-Bus
activation file so that it starts the supervised service instead of a second
daemon.

**buildiso wants two packages nobody asked for.** It copies
`boot/memtest86+/memtest.bin` and `usr/share/grub/themes/artix` out of the
build roots with no test, so `memtest86+` and `artix-grub-theme` are in the
list to stop it dying.

The build host also carries a one line patch to artools 0.39.1. Its
`configure_calamares()` ends on a directory test, so it returns 1 for any
profile that ships no Calamares, and `set -e` kills a finished rootfs. See
`docker/Dockerfile`.
