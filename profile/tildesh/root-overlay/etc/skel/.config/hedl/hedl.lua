-- tildesh on hedl. This replaces the sway config it grew out of.
--
-- The bar and the popups are wweft's job and kippsrv answers for everything
-- they show. Until those land this is the window manager alone, which is a
-- working desktop without either.

local mod  = "SUPER"
local term = "foot"

-- colors.lua is a link into the current theme, written when one is applied.
-- A theme change sends RELOAD through kippsrv, hedl runs this file again, and
-- the borders follow. Before the first theme there is no link, so the table
-- below is what a fresh image looks like.
local ok, colors = pcall(require, "colors")
if not ok then
  colors = {
    focus  = "#7aa2f7",
    border = "#292e42",
    urgent = "#f7768e",
    root   = "#1a1b26",
  }
end

hedl.config({
  general = { border_size = 2 },

  colors = colors,

  animation = { enabled = true, divisor = 6, snap = 2 },

  input = {
    follow_mouse = true,
    touchpad = { tap = true, natural_scroll = true },
  },
})

-- runit has no user service manager, so the session starts its own daemons.
-- These were `exec` lines in the sway config and mean the same thing here.
hedl.on("start", function()
  for _, cmd in ipairs({
    "pipewire", "pipewire-pulse", "wireplumber", "dunst",
    -- The idle daemon runs so that the bar's stay-awake toggle has something
    -- to turn off. swaybg is not started: no theme ships a background yet.
    "swayidle -w timeout 600 'swaylock -f'",
    -- The bar. It reads kippsrv, so it starts after it.
    "wweft ~/.config/tildesh-shell/bar.lua",
    -- The shell. Everything a surface draws comes off its socket, and it
    -- reads hedl over $XDG_RUNTIME_DIR/hedl/kipp rather than being a child.
    "kippsrv ~/.config/kippsrv/kippsrv.lua",
  }) do
    hedl.dsp.spawn(cmd)()
  end
end)

hedl.bind(mod .. " + Return",       "Terminal",     hedl.dsp.spawn(term))
hedl.bind(mod .. " + Q",            "Close window", hedl.dsp.killclient())
hedl.bind(mod .. " + D",            "What kippsrv says", hedl.dsp.spawn("test-wweft"))
hedl.bind(mod .. " + SHIFT + T",    "Theme",        hedl.dsp.spawn("wweft ~/.config/tildesh-shell/theme-picker.lua"))

-- The bar takes the keyboard while a mode holds and gives it back on Escape.
-- Nothing here knows what is in a group; the words are all hedl sends.
hedl.bind(mod .. " + space",        "Bar actions",  hedl.dsp.spawn("wweft --send bar 'mode centre'"))
hedl.bind(mod .. " + S",            "Bar panels",   hedl.dsp.spawn("wweft --send bar 'mode right'"))
-- Reload. hedl rereads this file, and the surfaces are started again so an
-- edit to one of them, or to shell.lua, takes hold too. A surface reads its
-- script once, at startup, so there is nothing else to tell it.
hedl.bind(mod .. " + SHIFT + R",    "Reload", function()
  hedl.dsp.reload()()
  hedl.dsp.spawn("pkill -x wweft; wweft ~/.config/tildesh-shell/bar.lua")()
end)
hedl.bind(mod .. " + SHIFT + E",    "Leave",        hedl.dsp.quit())

hedl.bind(mod .. " + J",            "Focus next",    hedl.dsp.focusstack(1))
hedl.bind(mod .. " + K",            "Focus prev",    hedl.dsp.focusstack(-1))
-- The same two under the arrows. Unbound, they reach the terminal instead and
-- it prints the tail of the escape the arrow sent.
hedl.bind(mod .. " + Right",        "Focus next",    hedl.dsp.focusstack(1))
hedl.bind(mod .. " + Down",         "Focus next",    hedl.dsp.focusstack(1))
hedl.bind(mod .. " + Left",         "Focus prev",    hedl.dsp.focusstack(-1))
hedl.bind(mod .. " + Up",           "Focus prev",    hedl.dsp.focusstack(-1))
hedl.bind(mod .. " + H",            "Shrink master", hedl.dsp.setmfact(-0.05))
hedl.bind(mod .. " + L",            "Grow master",   hedl.dsp.setmfact(0.05))
hedl.bind(mod .. " + M",            "Zoom",          hedl.dsp.zoom())

hedl.bind(mod .. " + F",            "Fullscreen",   hedl.dsp.togglefullscreen())
hedl.bind(mod .. " + SHIFT + space","Float window", hedl.dsp.togglefloating())
hedl.bind(mod .. " + T",            "Tile",         hedl.dsp.setlayout("tile"))
hedl.bind(mod .. " + V",            "Float all",    hedl.dsp.setlayout("floating"))
hedl.bind(mod .. " + B",            "Monocle",      hedl.dsp.setlayout("monocle"))

for i = 1, 9 do
  hedl.bind(mod .. " + " .. i, "Tag " .. i, hedl.dsp.view(i))
  -- Send the window and go with it. hedl.dsp.tag(i) on its own leaves you
  -- looking at the tag the window just left.
  hedl.bind(mod .. " + SHIFT + " .. i, "Move to " .. i .. " and follow", function()
    hedl.dsp.tag(i)()
    hedl.dsp.view(i)()
  end)
  hedl.bind(mod .. " + CTRL + " .. i,  "Also show " .. i, hedl.dsp.toggleview(i))
end

hedl.bind("XF86MonBrightnessUp",   nil, hedl.dsp.spawn("brightnessctl set +5%"))
hedl.bind("XF86MonBrightnessDown", nil, hedl.dsp.spawn("brightnessctl set 5%-"))
hedl.bind("XF86AudioRaiseVolume",  nil, hedl.dsp.spawn("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+"))
hedl.bind("XF86AudioLowerVolume",  nil, hedl.dsp.spawn("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"))
hedl.bind("XF86AudioMute",         nil, hedl.dsp.spawn("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"))
