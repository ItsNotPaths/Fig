# DE-shell

The visible desktop. Every piece here is a wweft surface or something one of
them runs.

```
lib/        shared Lua. Installed to ~/.config/wweft/lib/
surfaces/   one file for each surface. Installed to ~/.config/wweft/
theme/      the theme engine: render, link, poke. Ours, in Lua
vendor/     omarchy's setters, unmodified, for applications we do not ship
```

wweft puts the script's own directory, `$XDG_CONFIG_HOME/wweft/?.lua` and
`~/.config/wweft/?.lua` on `package.path`, so a surface reaches a library with
`require("lib.theme")` and needs no path of its own.

## One theme reader, not ten

A surface never parses a palette. It requires `lib/theme.lua`, which turns the
theme facts on the kipp stream into a table of colours and tells it when they
change. Adding a surface must not add a second copy of that logic, and
changing what a palette looks like must touch one file.

The same rule holds for anything else more than one surface needs.

## What runs where

The picker does the work. It renders omarchy's templates, writes the files,
swaps the current-theme link and runs `vendor/`'s setters, which is what keeps
a theme written for omarchy working here.

Then it sends twice. `wweft --send theme` reaches every surface that is up,
because a named channel is a FIFO at `$XDG_RUNTIME_DIR/wweft-<name>` and a
surface may listen on four of them beside the kippsrv socket. `RELOAD` on the
kippsrv socket reaches hedl, whose command channel kippsrv holds.

The signal carries the theme's name and nothing else, so a surface reacting to
it and a surface starting cold both end up calling `lib/theme.lua` the same
way. That is what stops a second code path for "I started late".
