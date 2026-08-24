-- tildesh on hedl. This replaces the sway config it grew out of.
--
-- The bar and the popups are wweft's job and kippsrv answers for everything
-- they show. Until those land this is the window manager alone, which is a
-- working desktop without either.

local mod  = "SUPER"
local term = "foot"

hedl.config({
  general = { border_size = 2 },

  colors = {
    focus  = "#7aa2f7",
    border = "#292e42",
    urgent = "#f7768e",
    root   = "#1a1b26",
  },

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
hedl.bind(mod .. " + SHIFT + C",    "Reload config", hedl.dsp.reload())
hedl.bind(mod .. " + SHIFT + E",    "Leave",        hedl.dsp.quit())

hedl.bind(mod .. " + J",            "Focus next",    hedl.dsp.focusstack(1))
hedl.bind(mod .. " + K",            "Focus prev",    hedl.dsp.focusstack(-1))
hedl.bind(mod .. " + H",            "Shrink master", hedl.dsp.setmfact(-0.05))
hedl.bind(mod .. " + L",            "Grow master",   hedl.dsp.setmfact(0.05))
hedl.bind(mod .. " + M",            "Zoom",          hedl.dsp.zoom())

hedl.bind(mod .. " + F",            "Fullscreen",   hedl.dsp.togglefullscreen())
hedl.bind(mod .. " + SHIFT + space","Float window", hedl.dsp.togglefloating())
hedl.bind(mod .. " + T",            "Tile",         hedl.dsp.setlayout("tile"))
hedl.bind(mod .. " + V",            "Float all",    hedl.dsp.setlayout("floating"))
hedl.bind(mod .. " + B",            "Monocle",      hedl.dsp.setlayout("monocle"))

for i = 1, 9 do
  hedl.bind(mod .. " + " .. i,         "Tag " .. i,     hedl.dsp.view(i))
  hedl.bind(mod .. " + SHIFT + " .. i, "Move to " .. i, hedl.dsp.tag(i))
end

hedl.bind("XF86MonBrightnessUp",   nil, hedl.dsp.spawn("brightnessctl set +5%"))
hedl.bind("XF86MonBrightnessDown", nil, hedl.dsp.spawn("brightnessctl set 5%-"))
hedl.bind("XF86AudioRaiseVolume",  nil, hedl.dsp.spawn("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+"))
hedl.bind("XF86AudioLowerVolume",  nil, hedl.dsp.spawn("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"))
hedl.bind("XF86AudioMute",         nil, hedl.dsp.spawn("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"))
