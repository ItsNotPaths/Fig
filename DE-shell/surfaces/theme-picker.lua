-- Pick a theme.
--
-- A list and a selection. No previews: a screenshot of a theme is a picture
-- of an older version of it, and drawing one costs an image decoder wweft
-- does not have. The colours here are the current theme, so the picker is
-- already showing you what a theme looks like.

local theme  = require("lib.theme")
local config = require("lib.config")
local apply  = require("theme.apply")

local c = theme.load()
local FG    = theme.argb(c.foreground)
local BG    = theme.argb(c.background, 0xf2)
local ACC   = theme.argb(c.accent)
local MUTED = theme.argb(c.muted)

local TITLE = Style.define(ACC, BG)
local ITEM  = Style.define(FG, BG)
local SEL   = Style.define(BG, ACC)
local MARK  = Style.define(MUTED, BG)

local ROWS = 12

local picker = {names = apply.list(), sel = 1, top = 1}
picker.current = apply.current_name()

for i, name in ipairs(picker.names) do
	if name == picker.current then picker.sel = i end
end

function picker:move(by)
	self.sel = math.max(1, math.min(#self.names, self.sel + by))
	self.top = math.max(self.sel - ROWS + 1, math.min(self.top, self.sel))
end

function picker:onKey(k)
	if k == "Down" or k == "j" then
		self:move(1)
	elseif k == "Up" or k == "k" then
		self:move(-1)
	elseif k == "Return" then
		local name = self.names[self.sel]
		if name then
			local ok, err = apply.apply(name)
			if not ok then print("theme: " .. tostring(err)) end
		end
		Surface.close(0)
	elseif k == "Escape" then
		Surface.close(1)
	else
		return false
	end
	return true
end

function picker:onDraw(g)
	g.fill(0, 0, g.cols, g.rows, ITEM)
	g.text(1, 0, "Theme", TITLE)

	for row = 0, ROWS - 1 do
		local i = self.top + row
		local name = self.names[i]
		if not name then break end

		local style = i == self.sel and SEL or ITEM
		g.fill(0, row + 2, g.cols, 1, style)
		g.text(1, row + 2, Text.clip(name, g.cols - 3), style)
		if name == self.current then
			g.text(g.cols - 2, row + 2, "*", i == self.sel and style or MARK)
		end
	end
end

local cfg = config.load()
Surface.font(cfg.font, cfg.size)
Surface.border("round", TITLE)
Surface.layer("overlay")
Surface.anchor("center")
Surface.window(28, ROWS + 2)
Surface.run(picker)
