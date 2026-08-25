-- Network. What you are on, and what else is in range.
--
--   Smith                    5 GHz · 1170 Mbit/s
--   Wi-Fi                                 ‹ on ›
--   Smith                     84 ‹ disconnect ›
--   CoffeeShop                55 ‹ join ›
--
--   Up/Down     move
--   Left/Right  change what is on the row: the radio, or what to do with a
--               network. A row offers only what makes sense for what it is
--   Return      do it
--   Escape      close
--
-- Everything that acts closes the popup. A connection takes seconds to settle
-- and the list under it is wrong the moment it starts, so the honest answer is
-- to get out of the way rather than draw a lie until it catches up.
--
-- A network that needs a password opens a terminal. nmcli stops and asks, and
-- a surface the bar spawned is nowhere for that question to appear.
--
-- Not the kippsrv net fact: it carries the connections that exist, which is
-- neither what is in the air nor how strong it is.

local palette = require("lib.palette")
local config  = require("lib.settings")

local HELPER = "net-status"

local MIN_COLS, MAX_COLS = 40, 60
local MAX_LIST = 8
local FIXED = 2          -- the status line and the radio, which never scroll

-- What a network can usefully be told, given what it is. The first is what
-- Return does; left and right walk the rest.
local ACTS = {
	active   = {"disconnect", "forget"},
	saved    = {"connect", "forget"},
	open     = {"connect"},
	secured  = {"join"},
}

palette.load()
local TEXT = palette.style("foreground", "background", 0xf2)
local DIM  = palette.style("dark_foreground", "background", 0xf2)
local HEAD = palette.style("accent", "background", 0xf2)
local SEL  = palette.style("background", "accent")

-- Surface.lines with a deadline of its own. A scan sweeps the air and the two
-- seconds the prelude allows is not enough for that.
local function lines(cmd, ms)
	local out = {}
	for line in Surface.sh(cmd, ms):gmatch("[^\n]+") do
		if line:match("%S") then out[#out + 1] = line end
	end
	return out
end

local function split(line)
	local f = {}
	for field in line:gmatch("[^\t]+") do f[#f + 1] = field end
	return f
end

local net = {name = "offline", detail = "", radio = "on", nets = {}, sel = 1, top = 1}

for _, line in ipairs(lines(HELPER, 4000)) do
	local f = split(line)
	if f[1] == "status" then
		net.name, net.detail = f[2] or "offline", f[3] or ""
	elseif f[1] == "radio" then
		net.radio = f[2] or "on"
	end
end

-- Read now and not on the key that shows it: a surface is sized once, and its
-- height is how many networks there are.
for _, line in ipairs(lines(HELPER .. " networks", 8000)) do
	local f = split(line)
	if f[1] == "net" then
		net.nets[#net.nets + 1] = {ssid = f[2], signal = f[3] or "0",
		                           acts = ACTS[f[4]] or ACTS.secured, at = 1}
	end
end

local LIST = math.max(1, math.min(#net.nets, MAX_LIST))

-- On the first network, not the radio: connecting is what this is opened for.
if #net.nets > 0 then net.sel = 2 end

local function width()
	local cols = MIN_COLS
	cols = math.max(cols, Grid.width(net.name) + Grid.width(net.detail) + 4)
	for _, n in ipairs(net.nets) do
		local act = 0
		for _, a in ipairs(n.acts) do act = math.max(act, Grid.width(a)) end
		cols = math.max(cols, Grid.width(n.ssid) + act + 12)
	end
	return math.min(cols, MAX_COLS)
end

function net:rows() return 1 + #self.nets end          -- the radio, then each network
function net:at(i) return self.nets[i - 1] end         -- 1 is the radio

function net:move(by)
	self.sel = math.max(1, math.min(self:rows(), self.sel + by))
	-- top counts networks, so it is the selection less the radio row.
	local want = math.max(1, self.sel - 1)
	self.top = math.max(want - LIST + 1, math.min(self.top, want))
end

function net:step(by)
	local n = self:at(self.sel)
	if not n then return end
	n.at = (n.at - 1 + by) % #n.acts + 1
end

-- Left and right on the radio row name a value rather than flipping one, so
-- a stray key press cannot take the network down.
function net:switch(to)
	if to == self.radio then return end
	Surface.spawn(("%s radio %s"):format(HELPER, to))
	Surface.close(0)
end

function net:fire()
	local n = self:at(self.sel)

	if not n then
		self:switch(self.radio == "on" and "off" or "on")
		return
	end

	local act = n.acts[n.at]
	Surface.spawn(("%s %s %s"):format(HELPER,
	              act == "join" and "join" or ("act " .. act), Text.quote(n.ssid)))
	Surface.close(0)
end

function net:onKey(k)
	if k == "Down" or k == "j" then
		self:move(1)
	elseif k == "Up" or k == "k" then
		self:move(-1)
	elseif k == "Left" or k == "h" then
		if self:at(self.sel) then self:step(-1) else self:switch("off") end
	elseif k == "Right" or k == "l" then
		if self:at(self.sel) then self:step(1) else self:switch("on") end
	elseif k == "Return" or k == "space" then
		self:fire()
	elseif k == "Escape" then
		Surface.close(0)
	else
		return false
	end
	return true
end

function net:onMessage(line)
	palette.changed(line)
end

function net:onDraw(g)
	g.fill(0, 0, g.cols, g.rows, TEXT)

	g.text(1, 0, Text.clip(self.name, g.cols - Grid.width(self.detail) - 3), HEAD)
	g.text(g.cols - Grid.width(self.detail) - 1, 0, self.detail, DIM)

	local on = self.sel == 1
	local pick = ("‹ %s ›"):format(self.radio)
	g.fill(0, 1, g.cols, 1, on and SEL or TEXT)
	g.text(1, 1, "Wi-Fi", on and SEL or TEXT)
	g.text(g.cols - Grid.width(pick) - 1, 1, pick, on and SEL or DIM)

	if #self.nets == 0 then
		g.text(1, FIXED, self.radio == "on" and "Nothing in range" or "The radio is off", DIM)
		return
	end

	for line = 0, LIST - 1 do
		local i = self.top + line
		local n = self.nets[i]
		if not n then break end

		local y = FIXED + line
		local sel = self.sel == i + 1
		local style = sel and SEL or TEXT
		local act = ("‹ %s ›"):format(n.acts[n.at])
		local at = g.cols - Grid.width(act) - 1

		g.fill(0, y, g.cols, 1, style)
		g.text(1, y, Text.clip(n.ssid, at - Grid.width(n.signal) - 3), style)
		g.text(at - Grid.width(n.signal) - 1, y, n.signal, sel and style or DIM)
		g.text(at, y, act, sel and style or DIM)
	end

	if self.top > 1 then g.text(g.cols - 1, FIXED, "▴", DIM) end
	if self.top + LIST - 1 < #self.nets then
		g.text(g.cols - 1, FIXED + LIST - 1, "▾", DIM)
	end
end

local cfg = config.load()
Surface.font(cfg.font, cfg.size)
Surface.border("round", HEAD)
Surface.layer("overlay")
Surface.anchor("top-right")
Surface.margin(cfg.gap, cfg.gap, 0, 0)
Surface.window(width(), FIXED + LIST)
Surface.listen("theme")
Surface.run(net)
