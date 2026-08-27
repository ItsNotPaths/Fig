-- kippsrv on fig. The window manager is hedl, and the adapters ship at
-- /usr/share/kippsrv/lua.
--
-- This file is here and not in /etc because nothing of ours goes in /etc. See
-- "Where our files live" in the README: /etc is for machine facts that have to
-- exist before anyone logs in, and a shell's source list is not one.
--
-- $VAR and ~ are expanded by kippsrv, so this file never reads the
-- environment and nothing in it can reach a variable it was not given.

local lua = "/usr/share/kippsrv/lua"

return {
	socket = "$XDG_RUNTIME_DIR/kippsrv.sock",
	state  = "$XDG_RUNTIME_DIR/kippsrv.state",

	sources = {
		-- The tray. Owning the name needs compiled code; naming the kind
		-- does not, so the registrations arrive at an adapter like anything
		-- else.
		{ name = "tray", watcher = true, adapter = lua .. "/tray/snw.lua" },

		-- Notifications, the same way and for the same reason: kippsrv owns
		-- org.freedesktop.Notifications, so it is the notification daemon
		-- rather than a reader of one. Nothing else on the image may hold
		-- that name, which is why dunst is not installed.
		{ name = "notify", notify = true, adapter = lua .. "/notify/fdo.lua" },

		-- hedl. One source and no seed: hedl sends its whole state when a
		-- consumer connects and again on every change, so there is nothing
		-- to prime. It is kipp on the wire already, which is why the
		-- adapter is a splitter and not a parser.
		--
		-- The path is derived, not inherited. kippsrv is not hedl's child
		-- and does not need to be, which is the whole point of D3.
		--
		-- `cmd` is the way back. hedl publishes on a socket and takes
		-- commands on a FIFO, so the two channels are two paths, and the
		-- adapter turns VIEW into the `view` its key table already runs.
		{ name = "wm", adapter = lua .. "/wm/hedl.lua",
		  sock = "$XDG_RUNTIME_DIR/hedl/kipp",
		  cmd  = "$XDG_RUNTIME_DIR/hedl/cmd" },

		-- bluez, on the system bus. The stream is named before the seed on
		-- purpose: both share the adapter file, and a command is answered by
		-- the first source that names it, which has to be the one holding a
		-- bus. The seed reads what is paired now; the stream carries every
		-- connect, battery and scan result after it.
		{ name = "bt", adapter = lua .. "/bt/bluez.lua", system = true,
		  dbus = {"type='signal',sender='org.bluez',interface='org.freedesktop.DBus.ObjectManager'",
		          "type='signal',sender='org.bluez',interface='org.freedesktop.DBus.Properties'"} },

		-- busctl is elogind's here, not systemd's. The image installs it for
		-- the seat, so the seed costs no package of its own.
		{ name = "bt-seed", adapter = lua .. "/bt/bluez.lua",
		  exec = {"busctl", "--system", "--json=short", "call", "org.bluez", "/",
		          "org.freedesktop.DBus.ObjectManager", "GetManagedObjects"} },

		{ name = "net", adapter = lua .. "/net/nm.lua",
		  exec = {"nmcli", "-t", "-f", "UUID,NAME,TYPE,DEVICE", "connection", "show"},
		  every = 5000 },

		-- steady: a person drives these, so backing off would mean pressing
		-- the volume key and waiting for the bar to notice.
		{ name = "audio", adapter = lua .. "/audio/pw.lua", steady = true,
		  exec = {"pactl", "list", "short", "sinks"}, every = 2000 },

		{ name = "backlight", adapter = lua .. "/backlight/brightnessctl.lua",
		  steady = true, exec = {"brightnessctl", "-m"}, every = 2000 },

		-- The weather. Somebody else's server, and a quarter of an hour is
		-- both often enough to be true and seldom enough to be polite. The
		-- adapter is ours and sits beside this file; `weather-fetch` is what
		-- knows where you are.
		{ name = "weather", adapter = "~/.config/kippsrv/weather.lua",
		  exec = {"weather-fetch"}, every = 900000 },

		{ name = "power", adapter = lua .. "/power/upower.lua",
		  exec = {"upower", "-d"}, every = 10000 },
	},
}
