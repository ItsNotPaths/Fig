# tildesh

An Artix image that boots to a Wayland session and nothing else.

tildesh is a desktop made of three programs — a window manager (`hedl`, a dwl
fork), a shell (`kippsrv`) and a renderer (`wweft`) — that speak one line
protocol. This repo is the ground they stand on: the package list, the ISO,
and a self test that checks the image on the image.

The image is built inside a container, so the only thing a build host needs is
docker.

## Where our files live

One rule: **nothing of ours goes in `/etc`.**

| Kind | Where | Example |
| --- | --- | --- |
| authored | `~/.config/<name>/` | `~/.config/hedl/hedl.lua` |
| runtime state | `$XDG_RUNTIME_DIR/<name>/` | `/run/user/1000/hedl/kipp` |
| durable state | `~/.local/state/<name>/` | `~/.local/state/tildesh/theme/` |
| installed | `/usr/share/<name>/` | `/usr/share/kippsrv/lua/` |
| on PATH | `/usr/bin/` | `/usr/bin/bar-actions` |

`/etc` is for machine facts that must exist before anyone logs in, like `fstab`
and `passwd`. A window manager's key table is not one, and `/etc/skel` is the
exception that proves it: a surface has to be the user's copy to be editable.

`kippsrv.lua` used to live in `/etc/tildesh/`. It is the reason this is written
down.

## Build

```sh
./download-deps.sh
./packaging/build-packages.sh
./scripts/build-iso.sh
```

`download-deps.sh` fetches what is not ours: four font faces, Artix's
iso-profiles to diff our own against, and omarchy's palettes, templates and
setters at a pinned tag. None of it is committed, so this tree holds no copy of
somebody else's 590 KB. Everything it writes is gitignored, as are `docs/`,
`repo/`, `dist/` and the `scripts/vm*` helpers.

`build-packages.sh` builds from the sibling repos beside this one and indexes
the result into `repo/`. Override the locations with `KIPPSRV_DIR`,
`WWEFT_DIR` and `HEDL_DIR`.

kippsrv and wweft are built on this machine and not in the container: kippsrv
is Odin, which is in no Artix repo, and wweft's build wants protocol sources
it vendors itself. Artix and Arch carry the same glibc, and neither binary
links anything else that moves. `ldd` after a build is the check.

hedl is built in the container, because nothing stops it: it is C, and
`wlroots0.20` and the rest are Artix packages. Only its source is staged.

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

## Self test

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
