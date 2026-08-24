# DE-shell

The visible desktop. Every piece here is a wweft surface or something one of
them runs.

```
shell.lua   what the shell is set to: the font and its size
lib/        shared Lua, required by surfaces
surfaces/   one file for each surface
theme/      the theme engine: palette, render, apply, setters
theme/templates/  {{ token }} config files, omarchy's and ours
themes/     the palettes, vendored
vendor/     omarchy's setters, unmodified, for applications we do not ship
```

Installed by the `tildesh-shell` package:

| From | To |
| --- | --- |
| `surfaces/*.lua`, `shell.lua` | `/etc/skel/.config/tildesh-shell/` |
| `lib/*.lua` | `/etc/skel/.config/tildesh-shell/lib/` |
| `theme/` | `/etc/skel/.config/tildesh-shell/theme/` |
| `themes/` | `/usr/share/tildesh/themes/` |
| `vendor/setters/`, `vendor/helpers/` | `/usr/share/tildesh/theme-setters/` |

Not `~/.config/wweft/`. That is wweft's own directory, and these files are no
more wweft's configuration than a script is bash's. wweft is a renderer that
lives on PATH, the way foot does, and the shell is what runs on it.

They go through `/etc/skel` because a surface has to be the user's copy to be
editable. wweft puts the running script's own directory first on
`package.path`, so `require("lib.theme")` resolves from wherever the surface
sits and needs no path of its own.

## One theme reader, not ten

A surface never parses a palette. It requires `lib/theme.lua`, which hands
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
2. Poke what we ship: foot by escape sequence, btop by signal, GTK by
   gsettings.
3. `wweft --send theme` to every surface that is up.
4. `RELOAD` on the kippsrv socket, which is how hedl hears about it, because
   kippsrv holds its command channel.
5. Run `vendor/`'s setters for everything else.

The signal carries the theme's name and nothing else, so a surface reacting to
it and a surface starting cold both end up in `lib/theme.lua` the same way.
That is what stops a second code path for "I started late".

## Compatibility

The palettes, the templates and the setters are omarchy's, unmodified, so a
theme written for omarchy works here and an upstream fix arrives as a diff.
`vendor/check.sh` reports what has drifted.

Every vendored setter reads `$HOME/.local/state/omarchy/current/theme`. That
path becomes a link to ours rather than a patch to fifteen files.
