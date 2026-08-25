-- The weather. What it is doing now, and the three days after this one.
--
--   Denver                          light rain
--
--    27°C   feels 26°
--    wind 13 km/h · humidity 34%
--
--   Tuesday          31°  17°
--   Wednesday        31°  18°
--
-- Nothing here asks anybody for anything. kippsrv runs `weather-fetch` every
-- quarter of an hour and publishes what came back, so this surface draws a
-- fact like every other one and the panel is open before the network would
-- have answered.
--
-- Escape closes it. There is nothing to press: weather is a thing to be told.

local kipp    = require("lib.kipp")
local palette = require("lib.palette")
local config  = require("lib.settings")
local sky     = require("lib.weather")

local COLS = 42
local ROWS = 8

palette.load()
local TEXT = palette.style("foreground", "background", 0xf2)
local DIM  = palette.style("dark_foreground", "background", 0xf2)
local HEAD = palette.style("accent", "background", 0xf2)
local LIT  = palette.style("accent", "background", 0xf2)

-- Monday, from what the forecast calls the day. Noon, so a clock change
-- either side of it still names the day that was asked for.
local function weekday(date)
	local y, m, d = date:match("^(%d+)-(%d+)-(%d+)$")
	if not y then return date end
	return os.date("%A", os.time({year = y, month = m, day = d, hour = 12}))
end

local wx = {facts = kipp.store()}

function wx:now()
	return self.facts:get("weather", "now")
end

function wx:onMessage(line)
	if palette.changed(line) then return end
	self.facts:feed(line)
end

function wx:onKey(k)
	if k == "Escape" or k == "Return" or k == "space" then
		Surface.close(0)
		return true
	end
	return false
end

function wx:onDraw(g)
	g.fill(0, 0, g.cols, g.rows, TEXT)

	local f = self:now()
	if not f then
		g.text(1, 0, "Weather", HEAD)
		g.text(1, 2, "Nothing yet", DIM)
		return
	end

	local a = f.attr
	local night = a.night == "1"
	local words = sky.words(a.code)

	g.text(1, 0, Text.clip(a.place or "", g.cols - Grid.width(words) - 3), HEAD)
	g.text(g.cols - Grid.width(words) - 1, 0, words, DIM)

	local temp = ("%s°%s"):format(a.temp or "?", a.unit or "C")
	g.text(1, 2, sky.glyph(a.code, night), LIT)
	g.text(4, 2, temp, TEXT)
	g.text(6 + Grid.width(temp), 2, ("feels %s°"):format(a.feels or "?"), DIM)

	g.text(1, 3, ("wind %s %s · humidity %s%%")
	             :format(a.wind or "?", a.unit == "F" and "mph" or "km/h",
	                     a.humidity or "?"), DIM)

	g.text(0, 4, ("─"):rep(g.cols), DIM)

	local y = 5
	for day in self.facts:each("forecast") do
		local d = day.attr
		local hi, lo = ("%s°"):format(d.hi or "?"), ("%s°"):format(d.lo or "?")

		g.text(1, y, weekday(d.date or ""), TEXT)
		g.text(g.cols - 12, y, sky.glyph(d.code), LIT)
		g.text(g.cols - Grid.width(hi) - Grid.width(lo) - 4, y, hi, TEXT)
		g.text(g.cols - Grid.width(lo) - 1, y, lo, DIM)

		y = y + 1
		if y >= ROWS then break end
	end
end

local cfg = config.load()
Surface.font(cfg.font, cfg.size)
Surface.border("round", HEAD)
Surface.layer("overlay")
Surface.anchor("top")
Surface.margin(cfg.gap, 0, 0, 0)
Surface.window(COLS, ROWS)
Surface.listen(kipp.socket)
Surface.listen("theme")
Surface.run(wx)
