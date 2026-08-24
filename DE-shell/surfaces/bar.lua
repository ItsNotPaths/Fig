-- The bar. One row, reserved, full width.
--
--   left    the tags that hold something, and the one being looked at
--   centre  the clock
--
-- Everything on the left arrives on the kippsrv socket, so the bar forks
-- nothing per second and knows nothing about the window manager. The clock is
-- the timer, and the timer is the only reason it redraws when nothing moved.
--
-- A tag that empties is not retracted: the last state anyone heard for it
-- stays true in the store. So live is decided here, from occupancy, and focus
-- is the most recent tag that said so. That is a consumer's job.
--
--   hedl.dsp.spawn("wweft ~/.config/wweft/bar.lua")

local kipp  = require("lib.kipp")
local theme = require("lib.theme")

-- Lua checks the format itself and refuses glibc's %-d, so the leading zero
-- comes off afterwards, and only the one after the weekday.
local CLOCK = "%a %d %b   %H:%M"

local function now()
	return (os.date(CLOCK):gsub("^(%a+) 0", "%1 "))
end
local FILL  = "·"
local TAGS  = 9

theme.load()
local BASE = theme.style("foreground", "background")
local DIM  = theme.style("dark_foreground", "background")
local ON   = theme.style("background", "accent")

local bar = {
	facts = kipp.store(),
	focus = 1,          -- the tag, not the monitor
	mon   = nil,
	clock = now(),
}

function bar:onTick()
	self.clock = now()
end

function bar:onMessage(line)
	-- A theme change rewrites the slots these ids name, so there is nothing
	-- to reassign here and the next frame is already the new colours.
	if theme.changed(line) then return end

	local kind = self.facts:feed(line)
	if kind == "focus" then
		local fact = self.facts:get("focus")
		self.mon = fact and fact.subj[1]
	elseif kind == "tag" then
		-- Whichever said focused last is the one being looked at. Arrival
		-- order is the only thing that settles it, so it is read here and
		-- not from the store.
		local _, subj, attr = kipp.parse(line)
		if attr and attr.state and attr.state:find("focused") then
			self.focus = tonumber(subj[2]) or self.focus
			self.mon = subj[1]
		end
	end
end

-- Occupied, plus the focused one, so a tag just switched to still has
-- something under the highlight.
function bar:live()
	local out = {}
	for fact in self.facts:each("tag") do
		local n = tonumber(fact.subj[2])
		if n and (not self.mon or fact.subj[1] == self.mon)
		   and fact.attr.state and fact.attr.state:find("occupied") then
			out[n] = true
		end
	end
	out[self.focus] = true

	local ids = {}
	for n = 1, TAGS do
		if out[n] then ids[#ids + 1] = n end
	end
	return ids
end

-- The fill glyph from one column to another, touching neither end. A glyph
-- the font cannot measure would never advance, so it steps one cell instead
-- of looping for ever.
local function run(g, from, to, style)
	local step = math.max(1, Grid.width(FILL))
	for x = from, to - 1, step do
		g.text(x, 0, FILL, style)
	end
end

function bar:onDraw(g)
	g.fill(0, 0, g.cols, g.rows, BASE)

	local x = 1
	for _, n in ipairs(self:live()) do
		local text = " " .. n .. " "
		g.text(x, 0, text, n == self.focus and ON or DIM)
		x = x + Grid.width(text)
	end

	local at = (g.cols - Grid.width(self.clock)) // 2
	g.text(at, 0, self.clock, BASE)
	run(g, x + 1, at - 1, DIM)
	run(g, at + Grid.width(self.clock) + 1, g.cols - 1, DIM)
end

Surface.font("", 16)
Surface.exclusive(1)      -- reserves the row, and so never takes the keyboard
Surface.dismiss(false)    -- a bar outlives every focus change
Surface.layer("top")
Surface.anchor("top")
Surface.every(1000)
Surface.listen(kipp.socket)
Surface.listen("theme")
Surface.window(0, 1)      -- 0 fills the axis
Surface.run(bar)
