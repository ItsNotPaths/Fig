-- The tray. What is registered, and the menu behind it.
--
--   [N] NordVPN
--   [S] Steam
--
--   Up/Down     move
--   Return      open what the item offers
--   Shift+Ret   ask the item for its context menu
--   Left/Esc    back a level, and close at the top
--   a letter    jump to the item whose name starts with it
--
-- kippsrv owns the StatusNotifierWatcher, which is the reason there is
-- anything here: a bus name has one owner, and an application with nowhere to
-- register exports no icon. Activating one is a call kippsrv already names, so
-- that goes up the socket. The names and the menus do not exist as facts, so
-- `tray-items` asks D-Bus for them.
--
-- Nearly every item reports ItemIsMenu, which the spec says means it has no
-- left click at all and the host shows its menu instead. So Return usually
-- opens a second level, which is a plain list of words. A menu is read when it
-- is opened rather than at startup: an application fills one when it is asked.

local kipp    = require("lib.kipp")
local palette = require("lib.palette")
local config  = require("lib.settings")

local HELPER = "tray-items"

local MIN_COLS, MAX_COLS = 34, 46
local MIN_LIST, MAX_LIST = 8, 12

palette.load()
local TEXT = palette.style("foreground", "background", 0xf2)
local DIM  = palette.style("dark_foreground", "background", 0xf2)
local HEAD = palette.style("accent", "background", 0xf2)
local SEL  = palette.style("background", "accent")

-- Empty fields count. A separator is an entry with no label, and a split that
-- drops empty fields would read its kind as its name.
local function split(line)
	local f = {}
	for field in (line .. "\t"):gmatch("([^\t]*)\t") do f[#f + 1] = field end
	return f
end

-- Surface.lines with a deadline of its own: an application answering for its
-- own menu is slower than the two seconds the prelude allows.
local function ask(cmd, ms)
	local out = {}
	for line in Surface.sh(cmd, ms):gmatch("[^\n]+") do
		if line:match("%S") then out[#out + 1] = split(line) end
	end
	return out
end

local tray = {items = {}, levels = {}, open = nil, sel = 1, top = 1}

for _, f in ipairs(ask(HELPER, 6000)) do
	if f[1] == "item" then
		tray.items[#tray.items + 1] = {
			service = f[2], path = f[3],
			title   = (f[4] ~= "" and f[4]) or f[2],
			is_menu = f[5] == "1",
		}
	end
end

local LIST = math.max(MIN_LIST, math.min(#tray.items, MAX_LIST))

local COLS = MIN_COLS
for _, it in ipairs(tray.items) do
	COLS = math.max(COLS, Grid.width(it.title) + 8)
end
COLS = math.min(COLS, MAX_COLS)

function tray:view()
	local level = self.levels[#self.levels]
	return level and level.rows or self.items
end

-- A separator is drawn and never landed on, and neither is a row an
-- application has greyed out.
function tray:landable(i)
	local row = self:view()[i]
	if not row then return false end
	return not self.open or (row.enabled and row.kind ~= "separator")
end

function tray:scroll()
	self.top = math.max(self.sel - LIST + 1, math.min(self.top, self.sel))
end

function tray:move(by)
	local n = #self:view()
	if n == 0 then return end

	local i = self.sel
	for _ = 1, n do
		i = (i - 1 + by) % n + 1
		if self:landable(i) then break end
	end
	self.sel = i
	self:scroll()
end

function tray:enter(rows)
	self.levels[#self.levels + 1] = {rows = rows}
	self.sel, self.top = 1, 1
	if not self:landable(1) then self:move(1) end
end

function tray:back()
	if #self.levels == 0 then return false end

	table.remove(self.levels)
	if #self.levels == 0 then self.open = nil end
	self.sel, self.top = 1, 1
	if not self:landable(1) then self:move(1) end
	return true
end

function tray:menu(id)
	return ask(("%s menu %s %s %s"):format(HELPER, Text.quote(self.open.service),
	           Text.quote(self.open.path), id), 6000)
end

function tray:rows_of(id)
	local rows = {}
	for _, f in ipairs(self:menu(id)) do
		if f[1] == "entry" then
			rows[#rows + 1] = {id = f[2], label = f[3] or "", kind = f[4] or "item",
			                   enabled = f[5] ~= "0", checked = f[6] == "1"}
		end
	end
	return rows
end

function tray:fire()
	local row = self:view()[self.sel]
	if not row then return end

	if not self.open then
		-- An item with a menu has no click of its own. One without opens on
		-- the socket, because the call belongs to the connection the watcher
		-- is on and kippsrv is holding it.
		if row.is_menu then
			self.open = row
			self:enter(self:rows_of(0))
		else
			kipp.send("ACTIVATE\t" .. row.service .. row.path)
			Surface.close(0)
		end
		return
	end

	if row.kind == "submenu" then
		self:enter(self:rows_of(row.id))
		return
	end

	Surface.spawn(("%s click %s %s %s"):format(HELPER, Text.quote(self.open.service),
	              Text.quote(self.open.path), row.id))
	Surface.close(0)
end

-- The initial, which is the whole reason it is drawn.
function tray:jump(letter)
	if self.open or letter == "" then return false end

	local want = letter:lower()
	for i, it in ipairs(self.items) do
		if it.title:sub(1, 1):lower() == want then
			self.sel = i
			self:scroll()
			return true
		end
	end
	return false
end

function tray:onKey(k)
	if k == "Down" or k == "j" then
		self:move(1)
	elseif k == "Up" or k == "k" then
		self:move(-1)
	elseif k == "Return" or k == "space" then
		self:fire()
	elseif k == "Shift+Return" then
		local row = self:view()[self.sel]
		if not self.open and row then
			kipp.send("MENU\t" .. row.service .. row.path)
			Surface.close(0)
		end
	elseif k == "Left" or k == "h" then
		if not self:back() then return false end
	elseif k == "Escape" then
		if not self:back() then Surface.close(0) end
	elseif not self:jump(Key.text) then
		return false
	end
	return true
end

function tray:onMessage(line)
	palette.changed(line)
end

function tray:draw_item(g, y, it, sel, style)
	g.fill(0, y, g.cols, 1, style)
	-- The first glyph, not the first byte: a name may start with anything.
	g.text(1, y, ("[%s]"):format(Text.clip(it.title, 1)), sel and style or HEAD)
	g.text(5, y, Text.clip(it.title, g.cols - 6), style)
end

function tray:draw_entry(g, y, row, sel, style)
	if row.kind == "separator" then
		g.text(1, y, ("─"):rep(g.cols - 2), DIM)
		return
	end

	g.fill(0, y, g.cols, 1, style)
	g.text(2, y, Text.clip(row.label, g.cols - 5), row.enabled and style or DIM)
	if row.checked then
		g.text(g.cols - 2, y, "✓", sel and style or HEAD)
	elseif row.kind == "submenu" then
		g.text(g.cols - 2, y, "›", sel and style or HEAD)
	end
end

function tray:onDraw(g)
	local view = self:view()
	g.fill(0, 0, g.cols, g.rows, TEXT)
	g.text(1, 0, Text.clip(self.open and self.open.title or "Tray", g.cols - 2), HEAD)

	if #view == 0 then
		g.text(1, 2, self.open and "Empty menu" or "Nothing registered", DIM)
		return
	end

	for line = 0, LIST - 1 do
		local i = self.top + line
		local row = view[i]
		if not row then break end

		local sel = i == self.sel
		local style = sel and SEL or TEXT
		if self.open then
			self:draw_entry(g, line + 1, row, sel, style)
		else
			self:draw_item(g, line + 1, row, sel, style)
		end
	end

	g.text(1, g.rows - 1,
	       self.open and "Return picks · Escape back" or "Return opens · Shift+Return menu",
	       DIM)

	if self.top > 1 then g.text(g.cols - 1, 1, "▴", DIM) end
	if self.top + LIST - 1 < #view then g.text(g.cols - 1, LIST, "▾", DIM) end
end

local cfg = config.load()
Surface.font(cfg.font, cfg.size)
Surface.border("round", HEAD)
Surface.layer("overlay")
Surface.anchor("top-right")
Surface.margin(cfg.gap, cfg.gap, 0, 0)
-- the title, the list, and the line that says what the keys do
Surface.window(COLS, LIST + 2)
Surface.listen("theme")
Surface.run(tray)
