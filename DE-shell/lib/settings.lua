-- What the shell is set to. One file read once, so ten surfaces do not each
-- invent a font size.

local M = {}

local HOME = os.getenv("HOME") or ""
local PATH = HOME .. "/.config/figshell/config.lua"

local DEFAULT = {font = "", family = "monospace", size = 16, size_foot = true,
                 clock = 12, gap = 8}

function M.load()
	local chunk, why = loadfile(PATH)
	local ok, t = pcall(chunk or function() return nil end)

	-- Falling back without a word is how a typo in config.lua looks exactly
	-- like the setting having no effect. Say which and why.
	if not chunk then
		io.stderr:write("figshell: ", tostring(why), "\n")
	elseif not ok then
		io.stderr:write("figshell: ", PATH, ": ", tostring(t), "\n")
	elseif type(t) ~= "table" then
		io.stderr:write("figshell: ", PATH, " returned no table\n")
	end
	if not ok or type(t) ~= "table" then t = {} end

	for key, fallback in pairs(DEFAULT) do
		if t[key] == nil then t[key] = fallback end
	end
	M.current = t
	io.stderr:write(("figshell: font %s at %d\n")
	                :format(t.font == "" and "(default)" or t.font, t.size))
	return t
end

-- foot reads a file and not a table, and foot.ini includes this one. Written
-- from here because the shell owns the size and foot only obeys it. A new
-- window is the next one to be the new size; ctrl+plus still wins per window.
function M.export()
	local cfg = M.current or M.load()
	if not cfg.size_foot then return end

	-- Two units for one number. wweft sizes a font by its height, ascent
	-- minus descent, and fontconfig's pixelsize is the em. For the face this
	-- image ships they are 1.25 apart: unitsPerEm 1000, ascent 965, descent
	-- -285. So the terminal is asked for four fifths of what the surfaces
	-- are, and the two come out the same height on screen.
	--
	-- pixelsize and not size, and no px suffix: size is points, and a
	-- pattern foot cannot parse leaves it on its own 8pt default.
	local em = math.floor(cfg.size * 0.8 + 0.5)
	local want = ("font=%s:pixelsize=%d\n"):format(cfg.family, em)
	local at = HOME .. "/.config/foot/size.ini"

	local old = io.open(at)
	if old then
		local same = old:read("a") == want
		old:close()
		if same then return end
	end

	os.execute("mkdir -p " .. HOME .. "/.config/foot")
	local f = io.open(at, "w")
	if not f then return end
	f:write(want)
	f:close()
end

return M
