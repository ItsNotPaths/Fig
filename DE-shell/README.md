# DE-shell

The visible desktop. Every piece here is a wweft surface or something one of
them runs.

```
config.lua        what you set: the typeface, its size, and the first theme
record.lua        what the record popup offers, and where the file lands
surfaces/         one file for each surface. Each one draws
bin/              what a surface runs, and kippnotif. On PATH, not beside it
lib/              code. Nothing here draws and nothing here is a setting
  settings.lua      reads config.lua
  palette.lua       the colours now, and when they changed
  kipp.lua          the facts off the kippsrv socket
  theme/            the theme engine, and the templates it renders
themes/           the palettes. Fetched, not committed
vendor/           the NOTICE for omarchy's setters, and check.sh
```

Installed by the `tildesh-shell` package:

| From | To |
| --- | --- |
| `config.lua`, `record.lua`, `surfaces/*.lua` | `/etc/skel/.config/tildesh-shell/` |
| `lib/` | `/etc/skel/.config/tildesh-shell/lib/` |
| `bin/*` | `/usr/bin/` |
| `themes/` | `/usr/share/tildesh/themes/` |
| `vendor/setters/` | `/usr/share/tildesh/theme-setters/` |
| `vendor/helpers/` | `/usr/share/tildesh/theme-setters/helpers/` |

Not `~/.config/wweft/`. That is wweft's own directory, and these files are no
more wweft's configuration than a script is bash's. wweft is a renderer that
lives on PATH, the way foot does, and the shell is what runs on it.

They go through `/etc/skel` because a surface has to be the user's copy to be
editable. wweft puts the running script's own directory first on
`package.path`, so `require("lib.palette")` resolves from wherever the surface
sits and needs no path of its own. A surface stays at the top of the
directory for that reason: from a subdirectory, `lib` would be looked for
beside it.

## One theme reader, not ten

A surface never parses a palette. It requires `lib/palette.lua`, which hands
back a table of colours and says when they changed. Adding a surface must not
add a second copy of that, and changing what a palette looks like must touch
one file.

The same rule holds for anything else more than one surface needs.

## What happens when a theme is picked

The picker does the work, in this order.

1. Build the theme beside the live one and move it into place, so a surface
   reading a colour sees the old theme or the new one and never half of each.
   A theme's own files are taken as they are; what it leaves out is rendered
   from a template.
2. Point the fixed paths at it. `~/.config/hedl/colors.lua` becomes a link
   into the new theme, and micro's `tildesh.micro` is copied over. Both are
   read by name, so the name stays and the file behind it changes.
3. Poke what we ship: foot by escape sequence on its own tty, btop by signal,
   GTK by gsettings, and swaybg for a theme that carries a picture.
4. `wweft --send theme` to every surface that is up.
5. `RELOAD` on the kippsrv socket, which is how hedl hears about it, because
   kippsrv holds its command channel.
6. Run `vendor/`'s setters for everything else.

The signal carries the theme's name and nothing else, so a surface reacting to
it and a surface starting cold both end up in `lib/palette.lua` the same way.
That is what stops a second code path for "I started late".

## Compatibility

The palettes, the templates and the setters are omarchy's, unmodified, so a
theme written for omarchy works here and an upstream fix arrives as a diff.
None of them are committed: `download-deps.sh` fetches them at a pinned tag
into the directories above, and `vendor/check.sh` reports what has drifted
against an installed omarchy.

Every vendored setter reads `$HOME/.local/state/omarchy/current/theme`. That
path becomes a link to ours rather than a patch to fifteen files.
