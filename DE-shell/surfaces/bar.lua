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
-- The tags arrive as one fact for the whole monitor, `used=` and `sel=`, so
-- that a switch between two empty tags is a line that changed. One fact for
-- each tag could only say "this one is no longer selected" by leaving it out,
-- and an omission is not something the store can pass on.
--
-- It holds the keyboard only while a mode holds. hedl binds send the word:
--
--   hedl.bind(mod .. " + space", "Bar", hedl.dsp.spawn("wweft --send bar 'mode centre'"))
--   hedl.dsp.spawn("wweft --send bar 'mode right'")
--
-- and hedl gives the keyboard back when the mode ends, which needs hedl
-- e94ec64.

local kipp   = require("lib.kipp")
local palette = require("lib.palette")
local config = require("lib.settings")

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

palette.load()
local BASE = palette.style("foreground", "background")
local DIM  = palette.style("dark_foreground", "background")
local ON   = palette.style("background", "accent")

local bar = {
	facts = kipp.store(),
	mon   = nil,        -- the monitor, from the focus fact
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
	if palette.changed(line) then return end

	local word, rest = line:match("^(%a+)%s*(.*)$")
	if word == "mode" then
		if rest == "" or rest == self.mode then self:leave() else self:enter(rest) end
		return
	end

	if self.facts:feed(line) == "focus" then
		local fact = self.facts:get("focus")
		self.mon = fact and fact.subj[1]
	end
end

-- ------------------------------------------------------------- drawing

local function numbers(list)
	local out = {}
	for n in (list or ""):gmatch("%d+") do out[tonumber(n)] = true end
	return out
end

-- What is in use, plus what is being looked at, so a tag just switched to
-- still has something under the highlight.
function bar:live()
	local fact = self.mon and self.facts:get("tags", self.mon)
	if not fact then
		for f in self.facts:each("tags") do
			fact = f
			break
		end
	end
	if not fact then return {}, {} end

	local used, sel = numbers(fact.attr.used), numbers(fact.attr.sel)
	local ids = {}
	for n = 1, TAGS do
		if used[n] or sel[n] then ids[#ids + 1] = n end
	end
	return ids, sel
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
	local ids, sel = self:live()
	for _, n in ipairs(ids) do
		local text = " " .. n .. " "
		g.text(x, 0, text, sel[n] and ON or DIM)
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

local cfg = config.load()
config.export()          -- the bar is the shell's long-lived process

Surface.font(cfg.font, cfg.size)
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
