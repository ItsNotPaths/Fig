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
--   hedl.bind(mod .. " + W", "Bar", hedl.dsp.spawn("wweft --send bar 'mode centre'"))
--   hedl.dsp.spawn("wweft --send bar 'mode right'")
--
-- and hedl gives the keyboard back when the mode ends, which needs hedl
-- e94ec64.

local kipp   = require("lib.kipp")
local palette = require("lib.palette")
local config = require("lib.settings")

-- Lua checks the format itself and refuses glibc's %-d, so leading zeros come
-- off afterwards: the one in the date, and the one on a 12 hour clock.
local CLOCK = {[12] = "%a %d %b   %I:%M %p", [24] = "%a %d %b   %H:%M"}

local function now(which)
	local text = (os.date(CLOCK[which] or CLOCK[24]):gsub("^(%a+) 0", "%1 "))
	-- 07:34 AM reads as a mistake where 09:04 does not, so only the 12 hour
	-- clock loses the zero on its hour.
	if which == 12 then text = (text:gsub("   0", "   ")) end
	return text
end

local FILL = "·"
local TAGS = 9

-- The centre group, in screen order, with the clock as the middle piece. A
-- row with no command draws and selects and does nothing, which is what a
-- panel that has not been written yet looks like.
--
-- The glyphs are omarchy's own, off the widgets in shell/plugins/bar, so the
-- desktop reads the same. What runs behind one is not: `bar-actions` names an
-- intent and decides for itself what the machine has to do about it.
--
-- A piece that puts a picker on the screen closes the mode, because slurp
-- wants the keyboard the bar is holding.
--
-- `on` names the toggle a piece stands for. A piece with one is drawn while
-- the group is closed too, whenever that toggle is on, so a night light left
-- running is something you can see rather than something to remember.
local CENTRE = {
	{icon = "󰔎", run = "bar-actions nightlight", on = "nightlight"},
	{icon = "󰢌", run = ""},                            -- reminder, wants a surface
	{icon = "󰅶", run = "bar-actions stayawake", on = "stayawake"},
	{icon = "",  clock = true, close = true,
	 run = "wweft ~/.config/tildesh-shell/calendar.lua"},
	{icon = "󰻂", run = "bar-actions record", on = "recording", close = true},
	{icon = "",  run = "bar-actions screenshot", close = true},
	{icon = "󰖐", run = ""},                            -- weather, a panel
}
-- Which piece the clock is. Found rather than written down, so adding a glyph
-- to the left of it is one line and not two.
local CLOCK_AT = 1
for i, item in ipairs(CENTRE) do
	if item.clock then CLOCK_AT = i end
end

-- The right group, in screen order, so notifications end up in the corner. No
-- panel behind any of these yet except the last.
--
-- Its label is not fixed: [!] while something is unread, [N] once everything
-- has been read, which is the whole of what the bar says about a notification.
-- Reading one means opening the panel, so the bar never has to draw a body.
local RIGHT = {
	{icon = "󰅀", run = ""},
	{icon = "󰂯", run = ""},
	{icon = "󰤨", run = ""},
	{icon = "󰕾", run = ""},
	{icon = "󰍹", run = "wweft ~/.config/tildesh-shell/display.lua", close = true},
	{notif = true, run = "wweft ~/.config/tildesh-shell/notifications.lua",
	 close = true},
}

palette.load()
-- Slot 0, so the few pixels past the last cell -- the screen is not a whole
-- number of cells wide -- are the bar's own background and not wweft's.
local BASE = palette.style("foreground", "background", nil, Style.base)
local DIM  = palette.style("dark_foreground", "background")
local ON   = palette.style("background", "accent")
-- The highlight box with the glyph washed out, for a toggle that is off.
local OFF  = palette.style("muted", "accent")
local LIT  = palette.style("accent", "background")

-- Which toggles are on. bar-actions writes it and moves it into place, and
-- wweft watches the directory, so the file does not have to exist yet.
local STATE = (os.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/tildesh"
local INDICATORS = STATE .. "/indicators"

local cfg = config.load()

local bar = {
	facts = kipp.store(),
	mon   = nil,        -- the monitor, from the focus fact
	clock = now(cfg.clock),
	mode  = nil,        -- nil, "centre" or "right"
	sel   = 1,
	on    = {},         -- the toggles that are on, by name
	unread = 0,         -- notif facts nobody has read
}

-- kippsrv owns the notification bus name and publishes one fact for each live
-- notification. The bar only counts them.
function bar:count()
	local n = 0
	for f in self.facts:each("notif") do
		if f.attr.read ~= "1" then n = n + 1 end
	end
	self.unread = n
end

function bar:read()
	local out, f = {}, io.open(INDICATORS)
	if f then
		for word in f:read("a"):gmatch("%S+") do out[word] = true end
		f:close()
	end
	self.on = out
end

function bar:onChange(path)
	self:read()
end

function bar:onTick()
	self.clock = now(cfg.clock)
end

-- ------------------------------------------------------------- the modes

function bar:group()
	return self.mode == "right" and RIGHT or CENTRE
end

-- Two pieces have a label rather than an icon, and both change under it.
function bar:label(items, i)
	if items[i].clock then return " " .. self.clock .. " " end
	if items[i].notif then return self.unread > 0 and " [!] " or " [N] " end
	return " " .. items[i].icon .. " "
end

function bar:enter(mode)
	self.mode = mode
	-- Each group opens on what it is usually opened for: the clock, which is
	-- the calendar, and the last piece on the right, which is notifications.
	-- The rest of either group is one key away.
	self.sel = mode == "right" and #RIGHT or CLOCK_AT
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
	elseif k == "Return" or k == "space" then
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

	local kind = self.facts:feed(line)
	if kind == "focus" then
		local fact = self.facts:get("focus")
		self.mon = fact and fact.subj[1]
	elseif kind == "notif" then
		self:count()
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

-- Everything while the group is open. Closed, the clock and whatever is on.
function bar:shown(items, i, mode)
	if self.mode == mode or items[i].clock then return true end
	return items[i].on ~= nil and self.on[items[i].on] == true
end

-- A toggle says which way it is set wherever it is drawn: lit while it is on,
-- and inside the highlight box, a glyph at full contrast against one washed
-- out. A piece that is not a toggle has no state to be in and stays plain.
function bar:style(items, i, mode)
	local item = items[i]
	local toggle = item.on ~= nil and self.on[item.on] == true

	if self.mode ~= mode then return item.clock and BASE or LIT end
	if self.sel == i then return item.on and not toggle and OFF or ON end
	if toggle then return LIT end
	return mode == "centre" and BASE or DIM
end

-- A run of pieces from x, lit where the selection is. Answers the column it
-- ended on.
function bar:band(g, items, from, to, x, mode)
	for i = from, to do
		if self:shown(items, i, mode) then
			local text = self:label(items, i)
			g.text(x, 0, text, self:style(items, i, mode))
			x = x + Grid.width(text)
		end
	end
	return x
end

function bar:width(items, from, to, mode)
	local w = 0
	for i = from, to do
		if self:shown(items, i, mode) then w = w + Grid.width(self:label(items, i)) end
	end
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
	local clock_w = Grid.width(self:label(CENTRE, CLOCK_AT))
	local clock_at = (g.cols - clock_w) // 2

	local left = self:width(CENTRE, 1, CLOCK_AT - 1, "centre")
	local from = math.max(clock_at - left, x + 1)

	self:band(g, CENTRE, 1, CLOCK_AT - 1, from, "centre")
	local ends = self:band(g, CENTRE, CLOCK_AT, CLOCK_AT, clock_at, "centre")
	ends = self:band(g, CENTRE, CLOCK_AT + 1, #CENTRE, ends, "centre")

	local right_at = g.cols - 1
	if self.mode == "right" then
		right_at = math.max(g.cols - self:width(RIGHT, 1, #RIGHT, "right") - 1, ends + 1)
		self:band(g, RIGHT, 1, #RIGHT, right_at, "right")
	end

	-- One blank cell either side of a run, so the dots never touch the text.
	fill(g, x + 1, from - 1, DIM)
	fill(g, ends + 1, right_at - 1, DIM)
end

config.export()          -- the bar is the shell's long-lived process

-- A home that has never had a theme picked has no palette, no foot colours
-- and no micro colourscheme. The shell themes itself once rather than
-- leaving everything on its built-in fallbacks. Loaded only when it is
-- needed, because the engine is no use to a bar otherwise.
local applied = io.open(os.getenv("HOME") .. "/.local/state/tildesh/theme/tildesh.lua")
if applied then
	applied:close()
else
	require("lib.theme.apply").apply(cfg.theme)
end

Surface.font(cfg.font, cfg.size)
Surface.exclusive(1)      -- reserves the row, so it takes no keyboard by default
-- The gap above the bar, so it lines up with hedl's window gaps. Set gap = 0
-- in config.lua to put it back against the edge.
Surface.margin(cfg.gap, 0, 0, 0)
Surface.dismiss(false)    -- a bar outlives every focus change
Surface.layer("top")
Surface.anchor("top")
Surface.every(1000)
Surface.listen(kipp.socket)
Surface.listen("theme")
Surface.listen("bar")
os.execute("mkdir -p " .. STATE)
Surface.watch(INDICATORS)
Surface.window(0, 1)      -- 0 fills the axis
bar:read()
Surface.run(bar)
