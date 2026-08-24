-- The applications we ship.
--
-- These are ours and in Lua because we run them and can tell when they break.
-- Everything else is a vendored script under DE-shell/vendor, unmodified.

local M = {}

local function popen(cmd)
	local out, lines = io.popen(cmd), {}
	if not out then return lines end
	for line in out:lines() do lines[#lines + 1] = line end
	out:close()
	return lines
end

-- A terminal takes its colours as escapes on its own tty, so a window that is
-- already open changes without being restarted.
local function osc_of(c)
	local out = {}
	for _, pair in ipairs({{10, "foreground"}, {11, "background"}, {12, "cursor"},
	                       {17, "selection_background"}, {19, "selection_foreground"}}) do
		if c[pair[2]] then
			out[#out + 1] = ("\27]%d;%s\7"):format(pair[1], c[pair[2]])
		end
	end
	for i = 0, 15 do
		local v = c["color" .. i]
		if v then out[#out + 1] = ("\27]4;%d;%s\7"):format(i, v) end
	end
	return table.concat(out)
end

function M.foot(c)
	local escapes = osc_of(c)
	if escapes == "" then return end

	for _, pid in ipairs(popen("pgrep -x foot 2>/dev/null")) do
		for _, child in ipairs(popen("pgrep -P " .. pid .. " 2>/dev/null")) do
			local tty = popen("readlink /proc/" .. child .. "/fd/1 2>/dev/null")[1]
			if tty and tty:find("^/dev/pts/") then
				local f = io.open(tty, "w")
				if f then
					f:write(escapes)
					f:close()
				end
			end
		end
	end
end

-- btop rereads its config on SIGUSR2.
function M.btop()
	os.execute("pkill -SIGUSR2 btop 2>/dev/null")
end

-- The whole of GTK theming, and it is a name and a mode. Generating a GTK
-- theme from the palette is a much bigger job for a much smaller return.
function M.gtk(c, dir)
	if not os.getenv("DBUS_SESSION_BUS_ADDRESS") then return end

	local light = c.mode == "light"
	local set = "gsettings set org.gnome.desktop.interface "
	os.execute(set .. "color-scheme " .. (light and "prefer-light" or "prefer-dark"))
	os.execute(set .. "gtk-theme " .. (light and "Adwaita" or "Adwaita-dark"))

	local f = io.open(dir .. "/icons.theme")
	local icons = f and f:read("l")
	if f then f:close() end
	os.execute(set .. "icon-theme '" .. (icons or "Adwaita") .. "'")
end

function M.all(c, dir)
	M.foot(c)
	M.btop()
	M.gtk(c, dir)
end

return M
