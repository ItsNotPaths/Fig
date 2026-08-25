-- Pick what to record.
--
--   top     the rows written in lists/record.lua, one press each
--   under   the sound, every monitor, and every window open right now
--
-- A window is not a monitor with a smaller box: it goes through the portal,
-- and the portal takes one target. So ticking a window drops the monitors and
-- ticking a monitor drops the window. Nothing else here is exclusive.
--
-- The windows come off the kippsrv socket as hedl's `cap` fact, whose subject
-- is the ext-foreign-toplevel-list identifier. That is the same string the
-- portal names a window by, so the popup never has to translate.

local kipp    = require("lib.kipp")
local palette = require("lib.palette")
local config  = require("lib.settings")

local HOME = os.getenv("HOME") or ""
local FILE = HOME .. "/.config/tildesh-shell/lists/record.lua"

local c = palette.load()
local BG    = palette.argb(c.background, 0xf2)
local TITLE = Style.define(palette.argb(c.accent), BG)
local ITEM  = Style.define(palette.argb(c.foreground), BG)
local SEL   = Style.define(BG, palette.argb(c.accent))
local MARK  = Style.define(palette.argb(c.muted), BG)

local COLS = 34
local SOUND = {"system", "none", "mic"}

local function settings()
	local chunk = loadfile(FILE)
	local ok, t = pcall(chunk or function() return nil end)
	if not ok or type(t) ~= "table" then t = {} end
	t.configs = t.configs or {}
	return t
end

-- The line a person wants to be on after pressing c. The first setting, with
-- the rows right under it, so one jump lands on the whole block.
local function config_line()
	local f = io.open(FILE)
	if not f then return 1 end
	local n = 0
	for line in f:lines() do
		n = n + 1
		if line:match("^%s*output%s*=") then break end
	end
	f:close()
	return math.max(1, n)
end

local rec = {
	facts = kipp.store(),
	cfg   = settings(),
	rows  = {},
	sel   = 1,
	sound = 1,
	mons  = {},    -- name -> true
	win   = nil,   -- an identifier, or nil
}

-- ------------------------------------------------------------- the rows

function rec:monitors()
	local out = {}
	for f in self.facts:each("mon") do out[#out + 1] = f.subj[1] end
	return out
end

function rec:focused()
	local f = self.facts:get("focus")
	return f and f.subj[1]
end

-- Rebuilt whenever a fact lands, because a window opening is a row appearing.
-- Four sections, a rule between any two that have anything in them. A machine
-- with no windows open should not grow a rule with nothing under it.
function rec:build()
	local quick, mons, wins = {}, {}, {}

	for _, one in ipairs(self.cfg.configs) do
		quick[#quick + 1] = {kind = "config", cfg = one}
	end
	for _, name in ipairs(self:monitors()) do
		mons[#mons + 1] = {kind = "mon", name = name}
	end
	for f in self.facts:each("cap") do
		wins[#wins + 1] = {kind = "win", id = f.subj[1],
		                   app = f.attr.app or "", title = f.attr.title or ""}
	end

	local rows = {}
	for _, section in ipairs({quick, {{kind = "sound"}}, mons, wins}) do
		if #section > 0 then
			if #rows > 0 then rows[#rows + 1] = {kind = "rule"} end
			table.move(section, 1, #section, #rows + 1, rows)
		end
	end

	self.rows = rows
	self.sel = math.max(1, math.min(#rows, self.sel))
	Surface.window(COLS, #rows + 2)
end

-- ------------------------------------------------------------- choosing

function rec:ticked(row)
	if row.kind == "mon" then return self.mons[row.name] end
	if row.kind == "win" then return self.win == row.id end
	return false
end

function rec:toggle(row)
	if row.kind == "sound" then
		self.sound = self.sound % #SOUND + 1
	elseif row.kind == "mon" then
		self.win = nil
		self.mons[row.name] = not self.mons[row.name] or nil
	elseif row.kind == "win" then
		self.mons = {}
		self.win = self.win ~= row.id and row.id or nil
	end
end

-- What `bar-actions capture` is given: the sound, then one target for each
-- thing ticked.
function rec:targets()
	local out = {}
	if self.win then
		out[1] = "win:" .. self.win
		return out
	end
	for _, name in ipairs(self:monitors()) do
		if self.mons[name] then out[#out + 1] = "mon:" .. name end
	end
	return out
end

-- A row from lists/record.lua names its monitors by intent rather than by
-- because the file is written before anyone knows what is plugged in.
function rec:from(one)
	local out = {}
	if one.monitors == "focused" then
		local name = self:focused()
		if name then out[1] = "mon:" .. name end
	elseif one.monitors == "all" then
		for _, name in ipairs(self:monitors()) do out[#out + 1] = "mon:" .. name end
	elseif type(one.monitors) == "table" then
		for _, name in ipairs(one.monitors) do out[#out + 1] = "mon:" .. name end
	end
	return out
end

function rec:start(sound, targets)
	if #targets == 0 then return end
	Surface.spawn(("bar-actions capture %s %s")
	              :format(sound, table.concat(targets, " ")))
	Surface.close(0)
end

function rec:fire()
	local row = self.rows[self.sel]
	if not row then return end
	if row.kind == "config" then
		self:start(row.cfg.audio or "none", self:from(row.cfg))
	else
		self:start(SOUND[self.sound], self:targets())
	end
end

-- ------------------------------------------------------------- input

function rec:move(by)
	local n = #self.rows
	if n == 0 then return end
	repeat
		self.sel = (self.sel - 1 + by) % n + 1
	until self.rows[self.sel].kind ~= "rule"
end

function rec:onKey(k)
	if k == "Down" or k == "j" then
		self:move(1)
	elseif k == "Up" or k == "k" then
		self:move(-1)
	elseif k == "space" then
		self:toggle(self.rows[self.sel] or {})
	elseif k == "Return" then
		self:fire()
	elseif k == "c" then
		Surface.spawn(("foot micro +%d %s"):format(config_line(), FILE))
		Surface.close(0)
	elseif k == "Escape" then
		Surface.close(1)
	else
		return false
	end
	return true
end

function rec:onMessage(line)
	if palette.changed(line) then return end
	local kind = self.facts:feed(line)
	if kind == "mon" or kind == "cap" or kind == "focus" then self:build() end
end

-- ------------------------------------------------------------- drawing

function rec:label(row)
	if row.kind == "config" then
		return row.cfg.name or "?", row.cfg.audio or "none"
	elseif row.kind == "sound" then
		return "Sound", SOUND[self.sound]
	elseif row.kind == "mon" then
		return row.name, "monitor"
	elseif row.kind == "win" then
		local name = row.app ~= "" and row.app or row.title
		return name, "window"
	end
	return "", ""
end

function rec:onDraw(g)
	g.fill(0, 0, g.cols, g.rows, ITEM)
	g.text(1, 0, "Record", TITLE)

	for i, row in ipairs(self.rows) do
		local y = i + 1
		if row.kind == "rule" then
			g.text(0, y, ("─"):rep(g.cols), MARK)
		else
			local style = i == self.sel and SEL or ITEM
			local name, note = self:label(row)
			g.fill(0, y, g.cols, 1, style)
			g.text(1, y, self:ticked(row) and "•" or " ", style)
			g.text(3, y, Text.clip(name, g.cols - 12), style)
			g.text(g.cols - Grid.width(note) - 1, y, note,
			       i == self.sel and style or MARK)
		end
	end
end

local cfg = config.load()
Surface.font(cfg.font, cfg.size)
Surface.border("round", TITLE)
Surface.layer("overlay")
Surface.anchor("center")
Surface.listen(kipp.socket)
Surface.listen("theme")
rec:build()
Surface.run(rec)
