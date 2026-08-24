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
DE-shell/
  config.lua        what the shell is set to
  surfaces/         the bar and the theme picker, drawn by wweft
  lib/              the theme engine and the kipp fact store
  themes/           the palettes
  vendor/           omarchy's theme setters, and the NOTICE for them
packaging/
  build-packages.sh build our packages, index them into repo/
  kippsrv/PKGBUILD  wraps a binary this machine built
  wweft/PKGBUILD    the same
  hedl-wm/PKGBUILD  compiles hedl in the container
  tildesh-shell/    DE-shell, split between /etc/skel and /usr/share
  tildesh-defaults/ plain files, kept beside their PKGBUILD
  ttf-iosevkaterm-nerd-mono/
                    four faces out of vendor/fonts
scripts/
  build-host.sh     build the container image
  build-iso.sh      build the ISO into dist/
download-deps.sh    fetch vendor/: the four font faces that ship, and
                    Artix's iso-profiles to diff our own against
```

`docs/`, `vendor/`, `repo/`, `dist/` and the `scripts/vm*` helpers are
gitignored. The only documents in the tree are this file and
`DE-shell/README.md`. Neither is installed.

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

The image is a UEFI live ISO. Boot it in any virtual machine with EFI firmware
and a GPU device. hedl wants a GPU: virtio-vga-gl is the fast path, and a plain
VGA card works on llvmpipe, because the image carries vulkan-swrast.

The live user is `tildesh`, the password is `tildesh`, and tty1 logs itself in
and starts hedl.

The image also runs a getty on ttyS0. A machine given a serial console needs
no window at all: log in there, run the self test, read the output.

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

`tildesh-selftest` is on the image, at `/usr/local/bin`. It runs hedl on the
headless wlroots backend, so it needs no GPU, no seat and no monitor. Run it
over ssh, in a VM, or from tty2 while the desktop is up. Its exit status is the
number of failed checks.

```
ok	hedl-headless
ok	hedl-cmd-fifo
ok	kipp-version
ok	kipp-mon
ok	kipp-focus
ok	kipp-tags
ok	kipp-layout
ok	kipp-sync
ok	kipp-version-first
ok	kipp-sync-after-state
ok	cmd-drives-state
ok	kipp-focus-subject
skip	kippsrv-hedl	kippsrv not installed
```

What it is for is the seam. hedl publishes kipp on a socket and takes commands
on a FIFO, so `cmd-drives-state` writes `setlayout` to the FIFO and looks for
the answer on the socket. `kipp-version-first` and `kipp-sync-after-state` are
the session order the spec asks for: a consumer that acts before `sync` is
acting on half a picture. `kipp-focus-subject` checks that a focus names a
monitor and not a tag, which is the mistake that makes every consumer draw
twice.

Three more checks put the same stream through kippsrv and look for it on the
other side. They need kippsrv and its hedl adapter installed; without them the
run prints `skip kippsrv-hedl` and stops, so the file is useful on an image
built before the shell is.

The test needs `hedl` and `socat` on PATH and nothing else, which is the fast
loop: build hedl in its own tree and point at it.

```sh
PATH=../hedl-wm:$PATH \
    profile/tildesh/root-overlay/usr/local/bin/tildesh-selftest
```

## What Artix decided for us

**The seat is elogind, not seatd.** `elogind-runit` and `seatd-runit` are
marked as conflicting, `base` depends on an `init-logind` that only elogind
provides, and polkit and the portals want the logind D-Bus API anyway.
`libseat` inside wlroots finds logind on its own.

**There is no user service manager.** runit has none, `turnstile` is packaged
for dinit and openrc but not for runit, and there is no `pipewire-runit`. So
the session starts its own daemons: `.bash_profile` runs `dbus-run-session
hedl`, and hedl's `start` hook spawns pipewire, pipewire-pulse, wireplumber,
dunst, swayidle, kippsrv and the bar. There is no `exec` on the hedl line, so a
compositor that dies leaves a shell on tty1 with its log beside it.

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
