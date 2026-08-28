# fig

A light Artix overlay:
 - lua driven glyph locked DE shell using [wweft]
 - lua composable universal IPC marshaller using [kipp] via [kippsrv]
 - [slopd] edits, browses, runs terminals, views images, and is every file
   dialog on the machine. One opinion, 2.7 MB, no toolkit
 - nothing heavy behind it (yazi/micro/btop/foot only - preconfigured)
 - omarchy vendored system themeing and styled DE shell layout
 - custom WM [hedl], lua configed dwl fork (1.75x) and light, hypr like visuals
 - full firmware/base-devel ready ootb

## Build

The image is built inside a container, so the only thing a build host needs is
docker.

```sh
./download-deps.sh
./packaging/build-packages.sh
./scripts/build-iso.sh
```

kippsrv and wweft are built on machine and not in the container: kippsrv
is Odin, which is in no Artix repo, and wweft's build wants protocol sources
it vendors itself. Artix and Arch carry the same glibc, and neither binary
links anything else that moves. `ldd` after a build is the check. hedl is 
built in the container.

`buildiso` reads `repo/` as `file:///repo`, through a pacman config the
container derives from the one artools ships.

## Run it

The image is a UEFI live ISO. Boot it in any virtual machine with EFI firmware
and a GPU device. 

The live user is `fig`, the password is `fig`, and tty1 logs itself in
and starts hedl.

The image also runs a getty on ttyS0. A machine given a serial console needs
no window at all: log in there, run the self test, read the output.

## Install it

`mod+a > Install`, or `install` in foot. LUKS2 and btrfs with
`@ @home @snapshots @log @pkg`. One password for the disk, the login and sudo.

## Looking at [kipp]

The session starts `kippsrv ~/.config/kippsrv/kippsrv.lua`, which reads hedl,
NetworkManager, PipeWire, backlight, power and the tray, and publishes the lot
on one socket.

It also answers on that socket, which is newer: it owns the tray's watcher
name, the notification name, xdg-desktop-portal's file chooser and
`org.freedesktop.FileManager1`. A file dialog arrives on the bus and leaves as
a `pick` line like any other fact — see **slopd** below.

`test-wweft` puts everything on that socket on a wweft surface. Mod+d, or the
command. `q` quits, `c` clears, `r` hides the raw lines.

The panel names no kind. It splits a line the way `kipp`'s spec says to, which
is the kind first, then the subject fields, then the attributes from the first
field holding an `=`. A fact no adapter writes yet shows up the day one does.

It is also the answer to whether wweft can read kippsrv without new C:
`Surface.listen` on a path connects to that socket and hands each line to
`onMessage`. That was already there for compositor event sockets.

## slopd

The one application the image is opinionated about, and the only graphical
program on it that is not part of the shell.

It is a text editor with tree-sitter highlighting, a file browser in list and
grid, real PTY terminals with sessions, an image viewer, a project search and
a command line that mixes shell commands with its own. Two panes, no modes.
That covers most of what a person does at a desktop, and it arrives as one
static 2.7 MB binary that links no toolkit.

So the "nothing heavy" line above still holds, but it is worth being straight
about the overlap: slopd edits and micro edits, slopd browses files and yazi
browses files, slopd runs terminals and foot runs terminals. Both of each are
on the image, and neither is in the other's way. `EDITOR` is still `micro`,
because `EDITOR` is a thing that opens in a terminal and slopd opens a window
unless you ask for `slopd --tui`. Change it if you would rather.

**It is not installed**, and that is deliberate. The package puts the binary
on PATH and the launcher entry beside it, and creates nothing under `~`.
`slopd --where` says so:

```
mode:      read-only
binary:    /usr/bin/slopd
```

Slopd runs on the defaults baked into its binary and starts owning files in
your home the day you ask it to, from its Config pane or `slopd --install`.
The package installed it; Slopd did not.

### Opening a folder

Its entry claims `inode/directory` and no text type, so opening a folder
anywhere lands in the file browser and no text file gains an Open With entry
it did not have. `~/.config/mimeapps.list` makes that the default rather than
one choice in a list.

### Saving a file

**slopd is also the save dialog.** kippsrv owns xdg-desktop-portal's FileChooser
backend, so a browser asking to save a file reaches this image's own browser
rather than a GTK window nothing here has a toolkit for.

```
Firefox  ──D-Bus──▶  xdg-desktop-portal  ──▶  kippsrv  ──kipp──▶  fig-files
                                                  ▲                    │
                                                  └────ANSWER──────────┴─▶ slopd
```

`pick` on the socket is a request with a token for a subject. `fig-files` runs
slopd on the folder it names, and whatever slopd returns goes back as
`ANSWER`. Shift+Enter in slopd stages `:return <path>` in its command line, so
turning `cat.png` into `cat-2.png` before pressing Enter is a text edit and
not a second dialog.

"Open containing folder" is the opposite shape and comes in on
`org.freedesktop.FileManager1`: a path handed over, nothing to answer. It
arrives as a `show` event and opens a window. kippsrv owns that name too,
which it can only do because there is no other file manager here to argue
over it.

None of it is D-Bus by the time it reaches `fig-files`, so anything that
speaks kipp can raise a `pick` itself and get the same dialog with no bridge
in the way.

**A toolkit only asks the portal when it is told to.** `.bash_profile` sets
`GTK_USE_PORTAL` and `QT_QPA_PLATFORMTHEME`, and Firefox gets a preference in
`/etc/firefox/policies/policies.json`. GTK 4 finds the portal on its own.
Nothing here is installed on the image, so each is a default waiting for the
day you install a browser. An application that draws its own file dialog and
asks no toolkit is out of reach, here as everywhere.

## Self test

`fig-selftest` is on the image, at `/usr/local/bin`. It runs hedl on the
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
    profile/fig/root-overlay/usr/local/bin/fig-selftest
```

## Super special thanks

This image is downstream of other people's work in ways a licence file does not
cover.

**[omarchy](https://omarchy.org/), and DHH.** The palettes, the templates and
the theme setters are omarchy's, vendored unmodified, so a theme written for
omarchy works here and an upstream fix arrives as a diff. The bar's glyphs are
off its widgets, its weather panel is where our WMO code table came from, and
`menu.lua` is its menu layout with our own commands behind it.

**[suckless](https://suckless.org/), and dwm and dmenu.** `lib/picker.lua` is
dmenu with more than one list behind it, and it is a small file only because
dmenu settled the hard question first: lines in, one line out, and the program
that asked decides what any of it meant. Half this repo is that idea wearing
different hats.

**[dwl](https://codeberg.org/dwl/dwl), and Devin J. Pohly and its
contributors.** hedl is a dwl fork. dwl did the part nobody thanks anybody
for, which is dwm's model on wlroots without the layers in between, and left a
window manager small enough that adding a Lua config and a kipp publisher was
an afternoon rather than a project.

Everything of theirs is under their own licence, and the vendored files carry
their notices. Anything wrong here is ours.

[slopd]: https://github.com/ItsNotPaths/Slopd
[wweft]: https://github.com/ItsNotPaths/wweft
[kipp]: https://github.com/ItsNotPaths/kipp
[kippsrv]: https://github.com/ItsNotPaths/kippsrv
[hedl]: https://github.com/ItsNotPaths/hedl-wm
