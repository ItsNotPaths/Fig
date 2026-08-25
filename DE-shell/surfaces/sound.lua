-- Sound. The master, which output it goes to, and every stream playing.
--
--   Sound                     ███████░░░  72%
--     Output       ‹ soundcore AeroFit 2 ›
--     Firefox                 ████░░░░░░  40%
--
--   Up/Down     move
--   Left/Right  change what is on the row: a volume, or which output
--   Return      mute and unmute
--   Escape      close
--
-- This one stays open while you use it. A volume is something you move and
-- listen to, not something you set once.
--
-- The state is read when it opens and then this surface owns the numbers: a
-- key press moves one and spawns the change. Reading it back would put a fork
-- between the key and the bar answering, which is the lag the shell exists to
-- avoid. Nothing here knows pactl -- `sound-state` names the three verbs and
-- decides for itself what the audio server is called this year.
--
-- Not the kippsrv sink fact: it carries what is plugged in, not what a person
-- calls it or which one is default, and neither a volume nor a stream.

local palette = require("lib.palette")
local config  = require("lib.settings")
local meter   = require("lib.meter")

local HELPER = "sound-state"

local MIN_COLS, MAX_COLS = 40, 60
local MAX_ROWS = 10
local GAUGE = 10
local STEP = 5

palette.load()
local TEXT   = palette.style("foreground", "background", 0xf2)
local DIM    = palette.style("dark_foreground", "background", 0xf2)
local HEAD   = palette.style("accent", "background", 0xf2)
local SEL    = palette.style("background", "accent")
local TROUGH = palette.style("muted", "muted", 0xf2)
local FILL   = palette.style("accent", "muted", 0xf2)

-- master, then the outputs, then one line for each stream. The order the
-- helper prints them in is the order they are drawn in.
local function read()
	local master, apps, sinks, at = nil, {}, {}, 1

	for _, line in ipairs(Surface.lines(HELPER)) do
		local f = {}
		for field in line:gmatch("[^\t]+") do f[#f + 1] = field end

		if f[1] == "master" then
			master = {name = "Sound", target = "@DEFAULT_SINK@",
			          vol = tonumber(f[2]) or 0, muted = f[3] == "1"}
		elseif f[1] == "sink" then
			sinks[#sinks + 1] = {name = f[2], desc = f[3] or f[2]}
			if f[4] == "1" then at = #sinks end
		elseif f[1] == "app" then
			apps[#apps + 1] = {name = f[3] or "audio", target = f[2],
			                   vol = tonumber(f[4]) or 0, muted = f[5] == "1"}
		end
	end

	-- A machine with no default sink still draws a panel. It says zero, which
	-- is what it is.
	local rows = {{level = master or
	               {name = "Sound", target = "@DEFAULT_SINK@", vol = 0, muted = false}},
	              {output = true}}
	for _, app in ipairs(apps) do rows[#rows + 1] = {level = app} end
	return rows, sinks, at
end

local sound = {sel = 1, top = 1}
sound.rows, sound.sinks, sound.at = read()

local ROWS = math.min(MAX_ROWS, #sound.rows)

-- Wide enough for the longest thing in it, within reason. A sink named by a
-- sentence is clipped rather than allowed to size the window.
local function width()
	local cols = MIN_COLS
	for _, s in ipairs(sound.sinks) do
		cols = math.max(cols, Grid.width(s.desc) + 14)
	end
	for _, row in ipairs(sound.rows) do
		if row.level then
			cols = math.max(cols, Grid.width(row.level.name) + GAUGE + 12)
		end
	end
	return math.min(cols, MAX_COLS)
end

function sound:move(by)
	self.sel = math.max(1, math.min(#self.rows, self.sel + by))
	self.top = math.max(self.sel - ROWS + 1, math.min(self.top, self.sel))
end

function sound:step(by)
	local row = self.rows[self.sel]

	if row.output then
		if #self.sinks == 0 then return end
		self.at = (self.at - 1 + by) % #self.sinks + 1
		Surface.spawn(("%s output %s"):format(HELPER, Text.quote(self.sinks[self.at].name)))
		return
	end

	local l = row.level
	l.vol = math.max(0, math.min(100, l.vol + by * STEP))
	Surface.spawn(("%s volume %s %d"):format(HELPER, Text.quote(l.target), l.vol))
end

function sound:flip()
	local row = self.rows[self.sel]
	if row.output then return end

	local l = row.level
	l.muted = not l.muted
	Surface.spawn(("%s mute %s %d"):format(HELPER, Text.quote(l.target), l.muted and 1 or 0))
end

function sound:onKey(k)
	if k == "Down" or k == "j" then
		self:move(1)
	elseif k == "Up" or k == "k" then
		self:move(-1)
	elseif k == "Left" or k == "h" then
		self:step(-1)
	elseif k == "Right" or k == "l" then
		self:step(1)
	elseif k == "Return" or k == "space" then
		self:flip()
	elseif k == "Escape" then
		Surface.close(0)
	else
		return false
	end
	return true
end

function sound:onMessage(line)
	palette.changed(line)
end

function sound:draw_level(g, y, level, on, style)
	local label = level.muted and "muted" or ("%d%%"):format(level.vol)
	local at = g.cols - Grid.width(label) - 1
	local from = at - GAUGE - 1

	g.text(1, y, Text.clip(level.name, from - 2),
	       (not on and level.target == "@DEFAULT_SINK@") and HEAD or style)
	if level.muted then
		g.text(from, y, ("─"):rep(GAUGE), on and style or DIM)
	else
		meter.draw(g, from, y, GAUGE, level.vol / 100, TROUGH, FILL)
	end
	g.text(at, y, label, on and style or DIM)
end

function sound:draw_output(g, y, on, style)
	local sink = self.sinks[self.at]
	-- The name is cut, not the brackets: a picker with one arrow on it reads
	-- as a bug rather than as a long name.
	local pick = ("‹ %s ›"):format(sink and Text.clip(sink.desc, g.cols - 14) or "none")

	g.text(1, y, "Output", style)
	g.text(g.cols - Grid.width(pick) - 1, y, pick, on and style or DIM)
end

function sound:onDraw(g)
	g.fill(0, 0, g.cols, g.rows, TEXT)

	for line = 0, g.rows - 1 do
		local i = self.top + line
		local row = self.rows[i]
		if not row then break end

		local on = i == self.sel
		local style = on and SEL or TEXT
		g.fill(0, line, g.cols, 1, style)
		if row.output then
			self:draw_output(g, line, on, style)
		else
			self:draw_level(g, line, row.level, on, style)
		end
	end

	if self.top > 1 then g.text(g.cols - 1, 0, "▴", DIM) end
	if self.top + ROWS - 1 < #self.rows then g.text(g.cols - 1, ROWS - 1, "▾", DIM) end
end

local cfg = config.load()
Surface.font(cfg.font, cfg.size)
Surface.border("round", HEAD)
Surface.layer("overlay")
Surface.anchor("top-right")
Surface.margin(cfg.gap, cfg.gap, 0, 0)
Surface.window(width(), ROWS)
Surface.listen("theme")
Surface.run(sound)
