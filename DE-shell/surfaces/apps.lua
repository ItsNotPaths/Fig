-- Run something. The applications this machine has, filtered as you type.
--
--   type        filter
--   Up/Down     move
--   Return      run it and close
--   Escape      close
--
-- The list comes from `app-list`, which reads the .desktop files and decides
-- what a terminal program has to be wrapped in. Everything else here is
-- lib/picker.lua, which is the same list-and-filter every other surface of
-- this shape wants.

local picker = require("lib.picker")
local config = require("lib.settings")

local COLS, ROWS = 52, 12

local function apps()
	local rows = {}
	-- A cold page cache makes this slower than the two seconds the prelude
	-- allows, and a launcher that opens empty is worse than one that waits.
	for line in Surface.sh("app-list", 5000):gmatch("[^\n]+") do
		local name, cmd = line:match("^([^\t]+)\t(.+)$")
		if name then rows[#rows + 1] = {text = name, value = cmd, search = cmd} end
	end
	return rows
end

local list = picker.new{
	prompt  = "Run",
	rows    = ROWS,
	sources = {{name = "apps", rows = apps}},

	pick = function(row)
		Surface.spawn(row.value)
		Surface.close(0)
	end,

	key = function(k)
		if k ~= "Escape" then return false end
		Surface.close(1)
		return true
	end,
}
list.empty = "Nothing installed by that name"

local cfg = config.load()
Surface.font(cfg.font, cfg.size)
Surface.border("round", list.style.title)
Surface.layer("overlay")
Surface.anchor("center")
Surface.window(COLS, ROWS + 1)      -- the query line, then the list
Surface.listen("theme")
Surface.run(list)
