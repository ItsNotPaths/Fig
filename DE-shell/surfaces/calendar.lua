-- The calendar. What the clock opens.
--
-- A month grid, today on a filled block, and a bar for how much of the year
-- has gone. Left and right walk the months, t returns to today, escape closes.
--
-- The dates are os.date and os.time, so there is no leap year arithmetic here
-- to be wrong every fourth February. Both take a month out of range and
-- normalise it, which is the whole of stepping between years.
--
-- The bar is the share of the year behind you, whole days completed over days
-- in the year, so 1 January reads 0% and 31 December reads 100%.

local palette = require("lib.palette")
local config  = require("lib.settings")
local meter   = require("lib.meter")

local COLS = 23
local ROWS = 10
local BAR = 12

local MONTHS = {"January", "February", "March", "April", "May", "June", "July",
                "August", "September", "October", "November", "December"}
-- Monday first.
local HEADS = {"Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"}

palette.load()
local TEXT   = palette.style("foreground", "background", 0xf2)
local DIM    = palette.style("dark_foreground", "background", 0xf2)
local HEAD   = palette.style("accent", "background", 0xf2)
local TODAY  = palette.style("background", "accent")
local TROUGH = palette.style("muted", "muted", 0xf2)
local FILL   = palette.style("accent", "muted", 0xf2)

-- Noon, so a day either side of a clock change is still the day asked for.
local function fields(y, m, d)
	return os.date("*t", os.time({year = y, month = m, day = d, hour = 12}))
end

-- Day 0 of the next month is the last day of this one.
local function days_in(y, m) return fields(y, m + 1, 0).day end

-- Which column the 1st sits in, Monday at 0. wday is 1 on Sunday.
local function lead(y, m) return (fields(y, m, 1).wday + 5) % 7 end

local today = os.date("*t")
local PROGRESS = (today.yday - 1) / fields(today.year, 12, 31).yday

local cal = {y = today.year, m = today.month}

function cal:step(by)
	local t = fields(self.y, self.m + by, 1)
	self.y, self.m = t.year, t.month
end

function cal:onKey(k)
	if k == "Left" or k == "h" then
		self:step(-1)
	elseif k == "Right" or k == "l" then
		self:step(1)
	elseif k == "t" or k == "T" then
		self.y, self.m = today.year, today.month
	elseif k == "Escape" or k == "Return" then
		Surface.close(0)
	else
		return false
	end
	return true
end

function cal:onDraw(g)
	g.fill(0, 0, g.cols, g.rows, TEXT)

	local title = ("%s %d"):format(MONTHS[self.m], self.y)
	g.text((g.cols - Grid.width(title)) // 2, 0, title, HEAD)

	for i = 1, 7 do
		g.text(i * 3 - 2, 1, HEADS[i], DIM)
	end

	-- Six rows always, so the window never changes height with the month.
	local first, days = lead(self.y, self.m), days_in(self.y, self.m)
	local now = self.y == today.year and self.m == today.month
	for w = 0, 5 do
		for i = 0, 6 do
			local n = w * 7 + i - first + 1
			if n >= 1 and n <= days then
				g.text(1 + i * 3, 2 + w, ("%2d"):format(n),
				       now and n == today.day and TODAY or TEXT)
			end
		end
	end

	local y = g.rows - 1
	local label = ("%d%%"):format(math.round(PROGRESS * 100))
	g.text(1, y, tostring(today.year), DIM)
	meter.draw(g, 6, y, BAR, PROGRESS, TROUGH, FILL)
	g.text(g.cols - Grid.width(label) - 1, y, label, DIM)
end

local cfg = config.load()
Surface.font(cfg.font, cfg.size)
Surface.border("round", HEAD)
Surface.layer("overlay")
Surface.anchor("top")
-- The bar reserves its row, so top is under it. The gap is the bar's own, to
-- sit as far off the bar as the bar sits off the edge.
Surface.margin(cfg.gap, 0, 0, 0)
Surface.window(COLS, ROWS)
Surface.run(cal)
