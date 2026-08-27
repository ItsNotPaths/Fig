-- Pick a theme.
--
--   type        filter
--   Up/Down     move
--   Return      apply it and close
--   Escape      close
--
-- No previews: a screenshot of a theme is a picture of an older version of
-- it, and drawing one costs an image decoder wweft does not have. The colours
-- here are the current theme, so the picker is already showing you what a
-- theme looks like.
--
-- The list and the filtering are lib/picker.lua, the same as every other
-- surface of this shape. What is left is where the names come from and what
-- picking one does.

local picker = require("lib.picker")
local config = require("lib.settings")
local apply  = require("lib.theme.apply")

local COLS, ROWS = 28, 12

local current = apply.current_name()

local function themes()
	local rows = {}
	for _, name in ipairs(apply.list()) do
		rows[#rows + 1] = {text = name, value = name,
		                   note = name == current and "*" or nil}
	end
	return rows
end

local list = picker.new{
	prompt  = "Theme",
	rows    = ROWS,
	sources = {{name = "themes", rows = themes}},

	pick = function(row)
		local ok, err = apply.apply(row.value)
		if not ok then io.stderr:write("theme: ", tostring(err), "\n") end
		Surface.close(0)
	end,

	key = function(k)
		if k ~= "Escape" then return false end
		Surface.close(1)
		return true
	end,
}
list.empty = "No theme by that name"

-- Open on the theme in use, so Return alone is a no-op rather than a change.
for i, row in ipairs(list.hits) do
	if row.value == current then list.sel = i end
end
list:move(0)

local cfg = config.load()
Surface.font(cfg.font, cfg.size)
Surface.border("round", list.style.title)
Surface.layer("overlay")
Surface.anchor("center")
Surface.window(COLS, ROWS + 1)
Surface.listen("theme")
Surface.run(list)
