-- Settings. How bright the screen is, how big everything on it is drawn, and
-- which way the machine is leaning on power.
--
--   Up/Down     move between the rows
--   Left/Right  change what is under the cursor
--   Return      apply the text size
--   Escape      close
--
-- Brightness lands as you go: brightnessctl answers at once and the screen
-- itself is the feedback. The text size cannot. A surface reads its font once,
-- at startup, and no layer surface resizes itself, so applying a size means
-- writing config.lua and starting the shell again. That is what Return is for,
-- and why it is not on every key press.
--
-- The brightness comes off the kippsrv socket as the backlight fact, so this
-- surface polls nothing. Setting it is a command, because kippsrv publishes
-- the backlight and does not drive it.
--
-- The power profile is not a kipp fact and does not need to be. It is read
-- once when the panel opens, which is when anyone can see it, and set with a
-- command like every other write in the shell. `powerprofilesctl list` gives
-- the whole answer in one fork: the profiles the machine offers, and a star
-- against the one in use.

local kipp    = require("lib.kipp")
local palette = require("lib.palette")
local config  = require("lib.settings")
local meter   = require("lib.meter")

local HOME = os.getenv("HOME") or ""
local SHELL = HOME .. "/.config/figshell"
local CONF = SHELL .. "/config.lua"

local COLS = 36
local GAUGE = 10
local STEP = 5           -- brightness, per key press
local MIN, MAX = 8, 48   -- pixels tall, the range config.lua's size may take
local ROWS = 3           -- brightness, text size, power

palette.load()
local TEXT   = palette.style("foreground", "background", 0xf2)
local DIM    = palette.style("dark_foreground", "background", 0xf2)
local HEAD   = palette.style("accent", "background", 0xf2)
local SEL    = palette.style("background", "accent")
local TROUGH = palette.style("muted", "muted", 0xf2)
local FILL   = palette.style("accent", "muted", 0xf2)

local cfg = config.load()

-- One line rewritten and every other one kept: config.lua is a file a person
-- edits, and it holds settings this surface knows nothing about.
local function write_size(px)
	local f = io.open(CONF)
	if not f then return nil, CONF .. " is not there" end

	local lines, done = {}, false
	for line in f:lines() do
		if line:match("^%s*size%s*=%s*%d+") then
			line = line:gsub("%d+", tostring(px), 1)
			done = true
		end
		lines[#lines + 1] = line
	end
	f:close()
	if not done then return nil, "no size line in " .. CONF end

	local out = io.open(CONF, "w")
	if not out then return nil, CONF .. " is not writable" end
	out:write(table.concat(lines, "\n"), "\n")
	out:close()
	return true
end

-- `* balanced:` for the one in use, `  performance:` for the rest, and four
-- indented lines under each that this does not read. A machine with no ppd
-- prints nothing here and the row says so rather than lying about a default.
local function read_power()
	local out = Surface.sh("powerprofilesctl list 2>/dev/null", 1500)
	local list, at = {}, nil
	for line in out:gmatch("[^\n]+") do
		local mark, name = line:match("^(.)%s(%S+):$")
		if name then
			list[#list + 1] = name
			if mark == "*" then at = #list end
		end
	end
	return list, at
end

local power, power_at = read_power()

local disp = {
	facts = kipp.store(),
	sel   = 1,
	dev   = nil,     -- what brightnessctl calls the backlight
	pct   = nil,     -- nil until the first fact arrives
	held  = false,   -- a key was pressed here, so the machine is no longer it
	size  = cfg.size,
	was   = cfg.size,
}

function disp:onMessage(line)
	if palette.changed(line) then return end
	if self.facts:feed(line) ~= "backlight" then return end

	-- brightnessctl lists keyboard LEDs too, and those are not the screen.
	for f in self.facts:each("backlight") do
		if f.attr.class == "backlight" then
			self.dev = f.subj[1]
			if not self.held then self.pct = tonumber(f.attr.percent) end
			break
		end
	end
end

function disp:step(by)
	if self.sel == 1 then
		if not self.dev then return end
		self.held = true
		self.pct = math.max(0, math.min(100, (self.pct or 0) + by * STEP))
		Surface.spawn(("brightnessctl -q -d %s set %d%%")
		              :format(Text.quote(self.dev), self.pct))
	elseif self.sel == 2 then
		self.size = math.max(MIN, math.min(MAX, self.size + by))
	else
		-- The ends stop rather than wrap: a profile list is ordered from
		-- least power to most, and rolling off one end onto the other is
		-- how you ask for quiet and get the fans.
		if not power_at then return end
		power_at = math.max(1, math.min(#power, power_at + by))
		Surface.spawn("powerprofilesctl set " .. Text.quote(power[power_at]))
	end
end

-- Writing the file is not what applies it. The shell is started again, and
-- this surface comes back with it at the size that was just chosen.
function disp:apply()
	if self.sel ~= 2 or self.size == self.was then return end

	local ok, err = write_size(self.size)
	if not ok then
		print("display: " .. tostring(err))
		return
	end
	Surface.spawn(("pkill -x wweft; wweft %s/bar.lua & wweft %s/display.lua &")
	              :format(SHELL, SHELL))
	Surface.close(0)
end

function disp:onKey(k)
	if k == "Down" or k == "j" then
		self.sel = math.min(ROWS, self.sel + 1)
	elseif k == "Up" or k == "k" then
		self.sel = math.max(1, self.sel - 1)
	elseif k == "Left" or k == "h" then
		self:step(-1)
	elseif k == "Right" or k == "l" then
		self:step(1)
	elseif k == "Return" or k == "space" then
		self:apply()
	elseif k == "Escape" then
		Surface.close(0)
	else
		return false
	end
	return true
end

function disp:row(g, y, name, on)
	g.fill(0, y, g.cols, 1, on and SEL or TEXT)
	g.text(1, y, name, on and SEL or TEXT)
end

function disp:onDraw(g)
	g.fill(0, 0, g.cols, g.rows, TEXT)
	g.text(1, 0, "Settings", HEAD)

	local on = self.sel == 1
	local label = self.pct and ("%d%%"):format(self.pct) or "--"
	local at = g.cols - Grid.width(label) - 1
	self:row(g, 2, "Brightness", on)
	meter.draw(g, at - GAUGE - 1, 2, GAUGE, (self.pct or 0) / 100, TROUGH, FILL)
	g.text(at, 2, label, on and SEL or DIM)

	on = self.sel == 2
	local size = ("‹ %d ›"):format(self.size)
	self:row(g, 3, "Text size", on)
	g.text(g.cols - Grid.width(size) - 1, 3, size, on and SEL or DIM)

	on = self.sel == 3
	local name = power_at and power[power_at] or "unavailable"
	self:row(g, 4, "Power", on)
	g.text(g.cols - Grid.width(name) - 1, 4, name, on and SEL or DIM)

	if self.size ~= self.was then
		g.text(1, 5, "Return applies, the shell restarts", DIM)
	end
end

Surface.font(cfg.font, cfg.size)
Surface.border("round", HEAD)
Surface.layer("overlay")
Surface.anchor("top-right")
Surface.margin(cfg.gap, cfg.gap, 0, 0)
-- title, a blank, the three rows, and the line that says what Return would do
Surface.window(COLS, 6)
Surface.listen(kipp.socket)
Surface.listen("theme")
Surface.run(disp)
