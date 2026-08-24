-- The bar. One row, reserved, full width.
--
--   left    the tags that hold something, and the one being looked at
--   centre  the clock, with the actions either side of it while that mode holds
--   right   the panels, in their own mode
--
-- Idle it is tags and a clock and nothing else, which is the point of putting
-- the rest behind a key. A group is drawn only in its own mode.
--
-- Everything on the left arrives on the kippsrv socket, so the bar forks
-- nothing per second and knows nothing about the window manager. The clock is
-- the timer, and the timer is the only reason it redraws when nothing moved.
--
-- A tag that empties is not retracted: the last state anyone heard for it
-- stays true in the store. So live is decided here, from occupancy, and focus
-- is the most recent tag that said so. That is a consumer's job.
--
-- It holds the keyboard only while a mode holds. hedl binds send the word:
--
--   hedl.bind(mod .. " + space", "Bar", hedl.dsp.spawn("wweft --send bar 'mode centre'"))
--   hedl.dsp.spawn("wweft --send bar 'mode right'")
--
-- and hedl gives the keyboard back when the mode ends, which needs hedl
-- e94ec64.

local kipp  = require("lib.kipp")
local theme = require("lib.theme")

-- Lua checks the format itself and refuses glibc's %-d, so the leading zero
-- comes off afterwards, and only the one after the weekday.
local CLOCK = "%a %d %b   %H:%M"

local function now()
	return (os.date(CLOCK):gsub("^(%a+) 0", "%1 "))
end

local FILL = "·"
local TAGS = 9

-- The centre group, in screen order, with the clock as the middle piece. A
-- row with no command draws and selects and does nothing, which is what a
-- panel that has not been written yet looks like.
local CENTRE = {
	{icon = "󰔎", run = "pkill -x wlsunset || wlsunset -t 4000 -T 6500"},
	{icon = "󰅶", run = "pkill -x swayidle || swayidle -w"},
	{icon = "",  clock = true},
	{icon = "",  run = "grim -g \"$(slurp)\"", close = true},
	{icon = "󰂛", run = "dunstctl set-paused toggle"},
}
local CLOCK_AT = 3

-- The right group. None of these panels exist yet.
local RIGHT = {
	{icon = "󰅀", run = ""},
	{icon = "󰂯", run = ""},
	{icon = "󰤨", run = ""},
	{icon = "󰕾", run = ""},
	{icon = "󰍹", run = ""},
}

theme.load()
local BASE = theme.style("foreground", "background")
local DIM  = theme.style("dark_foreground", "background")
local ON   = theme.style("background", "accent")

local bar = {
	facts = kipp.store(),
	focus = 1,          -- the tag, not the monitor
	mon   = nil,
	clock = now(),
	mode  = nil,        -- nil, "centre" or "right"
	sel   = 1,
}

function bar:onTick()
	self.clock = now()
end

-- ------------------------------------------------------------- the modes

function bar:group()
	return self.mode == "right" and RIGHT or CENTRE
end

-- The clock is the only piece whose label is not fixed.
function bar:label(items, i)
	if items[i].clock then return " " .. self.clock .. " " end
	return " " .. items[i].icon .. " "
end

function bar:enter(mode)
	self.mode = mode
	self.sel = mode == "centre" and CLOCK_AT or 1
	Surface.keyboard(true)
end

function bar:leave()
	self.mode = nil
	Surface.keyboard(false)
end

function bar:step(by)
	local n = #self:group()
	self.sel = (self.sel - 1 + by) % n + 1
end

-- Surface.spawn never blocks and never reports, which is right here: these
-- are fire and forget, and a failure is visible on screen anyway.
function bar:fire()
	local item = self:group()[self.sel]
	if item.run and item.run ~= "" then Surface.spawn(item.run) end
	-- A piece that opens something with a keyboard of its own has to be
	-- given the keyboard. A toggle keeps the mode, so the next one is one
	-- key away.
	if item.close then self:leave() end
end

function bar:onKey(k)
	if not self.mode then return false end

	if k == "Left" or k == "h" then
		self:step(-1)
	elseif k == "Right" or k == "l" then
		self:step(1)
	elseif k == "Return" then
		self:fire()
	elseif k == "Escape" then
		self:leave()
	else
		return false
	end
	return true
end

function bar:onMessage(line)
	-- A theme change rewrites the slots these ids name, so there is nothing
	-- to reassign here and the next frame is already the new colours.
	if theme.changed(line) then return end

	local word, rest = line:match("^(%a+)%s*(.*)$")
	if word == "mode" then
		if rest == "" or rest == self.mode then self:leave() else self:enter(rest) end
		return
	end

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

-- ------------------------------------------------------------- drawing

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
local function fill(g, from, to, style)
	local step = math.max(1, Grid.width(FILL))
	for x = from, to - 1, step do
		g.text(x, 0, FILL, style)
	end
end

-- A run of pieces from x, lit where the selection is. Answers the column it
-- ended on.
function bar:band(g, items, from, to, x, mode)
	for i = from, to do
		local text = self:label(items, i)
		local lit = self.mode == mode and self.sel == i
		g.text(x, 0, text, lit and ON or (mode == "centre" and BASE or DIM))
		x = x + Grid.width(text)
	end
	return x
end

function bar:width(items, from, to)
	local w = 0
	for i = from, to do w = w + Grid.width(self:label(items, i)) end
	return w
end

function bar:onDraw(g)
	g.fill(0, 0, g.cols, g.rows, BASE)

	local x = 1
	for _, n in ipairs(self:live()) do
		local text = " " .. n .. " "
		g.text(x, 0, text, n == self.focus and ON or DIM)
		x = x + Grid.width(text)
	end

	-- The clock is placed on its own width, so opening the group does not
	-- shove it sideways: the glyphs grow outwards from a fixed centre.
	local open = self.mode == "centre"
	local clock_w = Grid.width(self:label(CENTRE, CLOCK_AT))
	local clock_at = (g.cols - clock_w) // 2

	local left = open and self:width(CENTRE, 1, CLOCK_AT - 1) or 0
	local from = math.max(clock_at - left, x + 1)

	if open then self:band(g, CENTRE, 1, CLOCK_AT - 1, from, "centre") end
	local ends = self:band(g, CENTRE, CLOCK_AT, CLOCK_AT, clock_at, "centre")
	if open then ends = self:band(g, CENTRE, CLOCK_AT + 1, #CENTRE, ends, "centre") end

	local right_at = g.cols - 1
	if self.mode == "right" then
		right_at = math.max(g.cols - self:width(RIGHT, 1, #RIGHT) - 1, ends + 1)
		self:band(g, RIGHT, 1, #RIGHT, right_at, "right")
	end

	-- One blank cell either side of a run, so the dots never touch the text.
	fill(g, x + 1, from - 1, DIM)
	fill(g, ends + 1, right_at - 1, DIM)
end

Surface.font("", 16)
Surface.exclusive(1)      -- reserves the row, so it takes no keyboard by default
Surface.dismiss(false)    -- a bar outlives every focus change
Surface.layer("top")
Surface.anchor("top")
Surface.every(1000)
Surface.listen(kipp.socket)
Surface.listen("theme")
Surface.listen("bar")
Surface.window(0, 1)      -- 0 fills the axis
Surface.run(bar)
