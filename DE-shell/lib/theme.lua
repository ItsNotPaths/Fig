-- The palette, for a surface.
--
-- Every surface reads colours through this file. A second copy of this logic
-- is how a theme change starts repainting nine surfaces out of ten.
--
-- Two ways in, one path: a surface that starts after a theme change and a
-- surface that was up when it happened both end in load().

local M = {palette = nil}

local PATH = (os.getenv("HOME") or "") .. "/.local/state/tildesh/theme/tildesh.lua"

-- wweft styles are 0xAARRGGBB. A palette is "#rrggbb", because that is what
-- every other program on the machine reads.
function M.argb(hex, alpha)
	local h = tostring(hex):gsub("^#", "")
	local rgb = tonumber(h:sub(1, 6), 16)
	if not rgb then return 0xff000000 end
	return ((alpha or 0xff) << 24) | rgb
end

function M.load()
	local chunk = loadfile(PATH)
	local ok, t = pcall(chunk or function() return nil end)
	if not ok or type(t) ~= "table" then
		-- Enough to see the surface and read what is on it. A theme that
		-- will not load is a bug to see, not a black screen to guess at.
		t = {mode = "dark", background = "#1a1b26", foreground = "#c0caf5",
		     accent = "#7aa2f7", muted = "#565f89", red = "#f7768e"}
	end

	t.argb = M.argb
	M.palette = t
	return t
end

-- One line from the theme channel. Anything else is not ours.
function M.changed(line)
	if type(line) ~= "string" or not line:match("^theme%s") then return false end
	M.load()
	return true
end

return M
