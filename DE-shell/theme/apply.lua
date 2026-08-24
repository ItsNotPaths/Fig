-- Applying a theme.
--
-- Build the whole thing beside the live one, then move it into place. A
-- surface that reads a colour while this runs sees the old theme or the new
-- one, never half of each.
--
-- omarchy's setters are vendored unmodified so they keep tracking upstream,
-- and every one of them reads $HOME/.local/state/omarchy/current/theme. So
-- that path becomes a link to ours rather than a patch to fifteen files.

local palette = require("theme.palette")
local render  = require("theme.render")
local setters = require("theme.setters")

-- Every path is a field and none is a local, so a caller that moves `home`
-- moves all of them. A captured local looks the same and writes to the real
-- one, which is a thing that has happened twice.
local HOME = os.getenv("HOME") or "/root"

local M = {home = HOME}

M.state     = HOME .. "/.local/state/tildesh"
M.current   = M.state .. "/theme"
M.dirs      = {HOME .. "/.config/tildesh/themes", "/usr/share/tildesh/themes"}
M.templates = HOME .. "/.config/wweft/theme/templates"
M.setters   = "/usr/share/tildesh/theme-setters"
M.helpers   = M.setters .. "/helpers"
M.compat    = HOME .. "/.local/state/omarchy/current"

local function sh(cmd)
	return os.execute(cmd) and true or false
end

local function lines_of(cmd)
	local out, lines = io.popen(cmd), {}
	if not out then return lines end
	for line in out:lines() do lines[#lines + 1] = line end
	out:close()
	return lines
end

local function names_in(dir, kind)
	return lines_of(("find %s -mindepth 1 -maxdepth 1 -type %s -printf '%%f\\n' 2>/dev/null")
	                :format(dir, kind))
end

local function exists(path)
	local f = io.open(path)
	if f then f:close() end
	return f ~= nil
end

-- A name reaches a shell, so it is a name and not a sentence.
local function named(name)
	return type(name) == "string" and name ~= "" and not name:find("[^%w._-]")
end

-- A user theme of the same name wins, so a stock theme is customised by
-- naming one file rather than by copying twenty.
function M.dir(name)
	for _, d in ipairs(M.dirs) do
		if exists(d .. "/" .. name .. "/colors.toml") then
			return d .. "/" .. name
		end
	end
end

function M.list()
	local seen, names = {}, {}
	for _, d in ipairs(M.dirs) do
		for _, n in ipairs(names_in(d, "d")) do
			if not seen[n] and exists(d .. "/" .. n .. "/colors.toml") then
				seen[n] = true
				names[#names + 1] = n
			end
		end
	end
	table.sort(names)
	return names
end

function M.current_name()
	local f = io.open(M.state .. "/theme.name")
	if not f then return nil end
	local name = f:read("l")
	f:close()
	return name
end

-- Everything a theme ships is taken as it is. Everything it leaves out is
-- rendered from a template. A theme that ships its own foot.ini keeps it.
function M.build(name, into)
	if not named(name) then return nil, "a theme name is a name" end
	local from = M.dir(name)
	if not from then return nil, name .. " is not a theme here" end

	sh("rm -rf " .. into)
	sh("mkdir -p " .. into)
	sh("cp -r " .. from .. "/. " .. into .. "/ 2>/dev/null")
	sh("rm -rf " .. into .. "/backgrounds")

	local colors = palette.load(into .. "/colors.toml")
	if not colors then return nil, name .. " has no colors.toml" end

	for _, tpl in ipairs(names_in(M.templates, "f")) do
		local out = tpl:gsub("%.tpl$", "")
		if out ~= tpl and not exists(into .. "/" .. out) then
			render.file(colors, M.templates .. "/" .. tpl, into .. "/" .. out)
		end
	end
	return colors
end

function M.apply(name)
	local next_dir = M.state .. "/next-theme"
	local colors, err = M.build(name, next_dir)
	if not colors then return nil, err end

	sh("rm -rf " .. M.current)
	sh("mv " .. next_dir .. " " .. M.current)

	local f = io.open(M.state .. "/theme.name", "w")
	if f then
		f:write(name, "\n")
		f:close()
	end

	if not exists(M.compat .. "/theme") then
		sh("mkdir -p " .. M.compat)
		sh("ln -sfn " .. M.current .. " " .. M.compat .. "/theme")
	end

	-- hedl reads its four colours through a fixed path, so the link is made
	-- once and the RELOAD below is all a theme change costs it.
	sh("mkdir -p " .. M.home .. "/.config/hedl")
	sh("ln -sfn " .. M.current .. "/hedl-colors.lua " ..
	   M.home .. "/.config/hedl/colors.lua")

	M.poke(name, colors)
	return colors
end

-- The slow half. Every setter is a foreign application that has to be told,
-- and none of them is worth making a person wait for.
function M.poke(name, colors)
	setters.all(colors, M.current)

	sh("wweft --send theme 'theme " .. name .. "' 2>/dev/null &")
	sh("printf 'RELOAD\\n' | socat -t0 - UNIX-CONNECT:" ..
	   (os.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/kippsrv.sock 2>/dev/null &")

	-- The vendored half. helpers/ is on their PATH because they call each
	-- other by name, which is one more reason not to edit them.
	sh("PATH=" .. M.helpers .. ":$PATH; for s in " .. M.setters ..
	   "/*; do [ -f \"$s\" ] && [ -x \"$s\" ] && \"$s\"; done >/dev/null 2>&1 &")
end

return M
