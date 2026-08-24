-- What the shell is set to. One file read once, so ten surfaces do not each
-- invent a font size.

local M = {}

local HOME = os.getenv("HOME") or ""
local PATH = HOME .. "/.config/tildesh-shell/config.lua"

local DEFAULT = {font = "", family = "monospace", size = 16, size_foot = true}

function M.load()
	local chunk, why = loadfile(PATH)
	local ok, t = pcall(chunk or function() return nil end)

	-- Falling back without a word is how a typo in config.lua looks exactly
	-- like the setting having no effect. Say which and why.
	if not chunk then
		io.stderr:write("tildesh-shell: ", tostring(why), "\n")
	elseif not ok then
		io.stderr:write("tildesh-shell: ", PATH, ": ", tostring(t), "\n")
	elseif type(t) ~= "table" then
		io.stderr:write("tildesh-shell: ", PATH, " returned no table\n")
	end
	if not ok or type(t) ~= "table" then t = {} end

	for key, fallback in pairs(DEFAULT) do
		if t[key] == nil then t[key] = fallback end
	end
	M.current = t
	io.stderr:write(("tildesh-shell: font %s at %d\n")
	                :format(t.font == "" and "(default)" or t.font, t.size))
	return t
end

-- foot reads a file and not a table, and foot.ini includes this one. Written
-- from here because the shell owns the size and foot only obeys it. A new
-- window is the next one to be the new size; ctrl+plus still wins per window.
function M.export()
	local cfg = M.current or M.load()
	if not cfg.size_foot then return end

	local want = ("font=%s:size=%d\n"):format(cfg.family, cfg.size)
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
