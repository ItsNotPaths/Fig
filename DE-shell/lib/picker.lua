-- A filtered list, for any surface that is one.
--
-- dmenu with more than one list behind it. A source names its rows and says
-- when it is the live one, so a surface can show one thing while the query is
-- empty and another when it is not:
--
--   picker.new{
--     prompt = "Menu", rows = 10,
--     sources = {
--       {name = "here",   live = function(q) return q == "" end, rows = here},
--       {name = "search", live = function(q) return q ~= "" end, rows = every},
--     },
--     pick  = function(row) end,       -- Return, on the selected row
--     key   = function(k, self) end,   -- anything this file does not handle
--     moved = function(row, self) end, -- the selected row changed
--   }
--
-- One source and no `live` is plain dmenu, which is the point: the extra
-- layer costs nothing until something needs it.
--
-- A row is {text = , note = , value = }. text is drawn left, note right, and
-- value is what `pick` is handed. Nothing here knows what a row means.
--
-- A row may carry its own `style`, used when it is not the selected one. That
-- is for a list where a row means something on its own -- a critical
-- notification -- and not for decoration.
--
-- What this owns: the query, the filtering, the selection, the drawing. What
-- it does not: where the rows come from, what a pick does, and the window.
-- The caller sizes its own surface and calls Surface.run on what new() gives
-- back.

local palette = require("lib.palette")

local M = {}

local Picker = {}
Picker.__index = Picker

-- Case insensitive, on the text and on whatever else the row wants searched.
local function default_match(row, query)
	return Text.contains(row.text, query)
	       or (row.search ~= nil and Text.contains(row.search, query))
end

function M.new(opts)
	palette.load()

	local self = setmetatable({
		prompt  = opts.prompt or "",
		sources = opts.sources or {},
		rows    = opts.rows or 10,
		match   = opts.match or default_match,
		on_pick = opts.pick,
		on_key  = opts.key,
		on_moved = opts.moved,
		query   = "",
		sel     = 1,
		top     = 1,
		hits    = {},
		style   = opts.style or {
			title = palette.style("accent", "background", 0xf2),
			item  = palette.style("foreground", "background", 0xf2),
			sel   = palette.style("background", "accent"),
			dim   = palette.style("dark_foreground", "background", 0xf2),
		},
	}, Picker)

	self:reload()
	return self
end

-- Which source answers for the query as it stands. First one wins, so an
-- overlap is decided here rather than by luck.
function Picker:source()
	for _, src in ipairs(self.sources) do
		if not src.live or src.live(self.query) then return src end
	end
end

-- Ask the live source for its rows, then filter them. Call it when whatever
-- is behind a source has changed.
function Picker:reload()
	local src = self:source()

	if src ~= self.at then
		-- A new source is a new list, so the cursor starts again. The query
		-- is what chose the source, so it stays.
		self.at, self.sel, self.top = src, 1, 1
		self.all = src and src.rows() or {}
	end
	self:filter()
end

-- Ask the live source again and keep the cursor where it can be kept. For a
-- caller whose rows changed underneath it: a fact arrived, a scan finished.
function Picker:refresh()
	local src = self:source()

	self.at = src
	self.all = src and src.rows() or {}
	self:filter()
end

function Picker:filter()
	local hits = {}
	for _, row in ipairs(self.all or {}) do
		if self.query == "" or self.match(row, self.query) then
			hits[#hits + 1] = row
		end
	end

	self.hits = hits
	self.sel = math.max(1, math.min(#hits, self.sel))
	self.top = math.max(self.sel - self.rows + 1, math.min(self.top, self.sel))
	self:settle()
end

-- `moved` fires when the selected row changes and not on every key. A surface
-- that follows the selection with something expensive, a preview process for
-- one, should not pay for a keystroke that moved nothing: typing a letter that
-- filters nothing out leaves the same row selected, and so does Down at the
-- bottom of the list.
function Picker:settle()
	local row = self.hits[self.sel]
	if row == self.on then return end
	self.on = row
	if self.on_moved then self.on_moved(row, self) end
end

function Picker:move(by)
	if #self.hits == 0 then return end
	self.sel = math.max(1, math.min(#self.hits, self.sel + by))
	self.top = math.max(self.sel - self.rows + 1, math.min(self.top, self.sel))
	self:settle()
end

function Picker:type(text)
	self.query = self.query .. text
	self.sel, self.top = 1, 1
	self:reload()
end

function Picker:erase()
	if self.query == "" then return false end
	self.query = Text.chop(self.query)
	self.sel, self.top = 1, 1
	self:reload()
	return true
end

function Picker:clear()
	if self.query == "" then return false end
	self.query = ""
	self.sel, self.top = 1, 1
	self:reload()
	return true
end

function Picker:selected()
	return self.hits[self.sel]
end

function Picker:onKey(k)
	if k == "Down" or k == "Ctrl+n" then
		self:move(1)
	elseif k == "Up" or k == "Ctrl+p" then
		self:move(-1)
	elseif k == "Return" then
		local row = self:selected()
		if row and self.on_pick then self.on_pick(row, self) end
	elseif k == "BackSpace" then
		if not self:erase() and self.on_key then return self.on_key(k, self) end
	elseif k == "Ctrl+u" then
		self:clear()
	elseif Key.text ~= "" and k ~= "Escape" then
		self:type(Key.text)
	elseif self.on_key then
		return self.on_key(k, self)
	else
		return false
	end
	return true
end

-- The prompt on the top row, the list under it. A caller that wants a footer
-- leaves it a row and draws its own.
function Picker:onDraw(g)
	local s = self.style
	g.fill(0, 0, g.cols, g.rows, s.item)

	local head = self.prompt ~= "" and (self.prompt .. "  ") or ""
	g.text(1, 0, head, s.title)
	g.text(1 + Grid.width(head), 0, Text.clip(self.query, g.cols - 2), s.item)

	if #self.hits == 0 then
		g.text(1, 2, self.empty or "Nothing", s.dim)
		return
	end

	for line = 0, self.rows - 1 do
		local row = self.hits[self.top + line]
		if not row then break end

		local on = self.top + line == self.sel
		local style = on and s.sel or (row.style or s.item)
		local y = line + 1
		local note = row.note or ""

		g.fill(0, y, g.cols, 1, style)
		g.text(1, y, Text.clip(row.text, g.cols - Grid.width(note) - 3), style)
		if note ~= "" then
			g.text(g.cols - Grid.width(note) - 1, y, note, on and style or s.dim)
		end
	end

	if self.top > 1 then g.text(g.cols - 1, 1, "▴", s.dim) end
	if self.top + self.rows - 1 < #self.hits then
		g.text(g.cols - 1, self.rows, "▾", s.dim)
	end
end

return M
