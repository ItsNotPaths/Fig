-- What has arrived, and nothing else.
--
-- The bar says only [!] or [N]. A body is read here, on purpose: a toast that
-- appears over what you are doing is an interruption whether or not it was
-- worth one, and this is the same information without that.
--
-- kippsrv owns org.freedesktop.Notifications and publishes one `notif` fact
-- for each live one. Nothing here talks to D-Bus, and nothing here decides
-- when a notification dies -- Delete sends the word back up the socket and the
-- fact going away is what removes the row.
--
--   notif  <id>  app=grim  summary=Screenshot saved  body=...  urgency=normal
--                read=0    exec=satty -f /home/x/Pictures/a.png
--
-- The body of whatever is selected fills the box underneath, so reading one
-- costs no keys. Return is left for running the thing rather than expanding it,
-- because a notification worth opening is worth opening in one press.
--
--   Up/Down     move
--   Return      run `exec`, if the notification carries one
--   Delete      dismiss it
--   Escape      close

local kipp    = require("lib.kipp")
local palette = require("lib.palette")
local config  = require("lib.settings")

local c = palette.load()
local BG    = palette.argb(c.background, 0xf2)
local TITLE = Style.define(palette.argb(c.accent), BG)
local ITEM  = Style.define(palette.argb(c.foreground), BG)
local SEL   = Style.define(BG, palette.argb(c.accent))
local MUTED = Style.define(palette.argb(c.muted), BG)
local URGENT = Style.define(palette.argb(c.red), BG)

local COLS = 52
local ROWS = 10       -- the list
local BODY = 4        -- the box under it

-- Break a line to fit, on spaces where there is one and mid-word where there
-- is not, because a path with no spaces in it still has to be readable.
local function wrap(text, cols, lines)
	local out = {}
	for _, para in ipairs({text}) do
		local rest = para
		while rest ~= "" and #out < lines do
			if Grid.width(rest) <= cols then
				out[#out + 1] = rest
				break
			end
			local cut = cols
			for i = cols, math.floor(cols / 2), -1 do
				if rest:sub(i, i) == " " then cut = i - 1 break end
			end
			out[#out + 1] = rest:sub(1, cut)
			rest = rest:sub(cut + 1):gsub("^%s+", "")
		end
	end
	return out
end

local panel = {facts = kipp.store(), rows = {}, sel = 1, top = 1, read = false}

-- Newest last, which is the order kippsrv sent them in, so a list that grows
-- while it is open does not move what is under the cursor.
function panel:build()
	local rows = {}
	for f in self.facts:each("notif") do
		rows[#rows + 1] = {
			id      = f.subj[1],
			app     = f.attr.app or "",
			summary = f.attr.summary or "",
			body    = f.attr.body or "",
			urgent  = f.attr.urgency == "critical",
			exec    = f.attr.exec or "",
		}
	end
	self.rows = rows
	self.sel = math.max(1, math.min(#rows, self.sel))
	self.top = math.max(self.sel - ROWS + 1, math.min(self.top, self.sel))

	-- Opening the panel is what reading is, and it is said once. kippsrv
	-- republishes each fact with read=1, which arrives here as another notif
	-- line: saying it again for those would never stop.
	if not self.read and #rows > 0 then
		self.read = true
		kipp.send("NOTIFY-READ")
	end
end

function panel:move(by)
	if #self.rows == 0 then return end
	self.sel = math.max(1, math.min(#self.rows, self.sel + by))
	self.top = math.max(self.sel - ROWS + 1, math.min(self.top, self.sel))
end

-- Uppercase, up the socket kippsrv is already listening on. The fact
-- disappearing is what takes the row away, so nothing is removed here.
function panel:say(word)
	local row = self.rows[self.sel]
	-- A tab. kipp separates the kind from its subject with one, and a space
	-- makes the whole line one field that no adapter claims.
	if row then kipp.send(word .. "\t" .. row.id) end
end

function panel:onKey(k)
	if k == "Down" or k == "j" then
		self:move(1)
	elseif k == "Up" or k == "k" then
		self:move(-1)
	elseif k == "Return" then
		local row = self.rows[self.sel]
		if row and row.exec ~= "" then
			Surface.spawn(row.exec)
			self:say("NOTIFY-CLOSE")
			Surface.close(0)
		end
	elseif k == "Delete" or k == "BackSpace" then
		self:say("NOTIFY-CLOSE")
	elseif k == "Escape" then
		Surface.close(1)
	else
		return false
	end
	return true
end

function panel:onMessage(line)
	if palette.changed(line) then return end
	-- Every fact is read, and only ours changes the list. Marking them read is
	-- kippsrv's to record, so that a second surface sees the same thing.
	if self.facts:feed(line) == "notif" then self:build() end
end

function panel:onDraw(g)
	g.fill(0, 0, g.cols, g.rows, ITEM)
	g.text(1, 0, "Notifications", TITLE)

	if #self.rows == 0 then
		g.text(1, 2, "Nothing waiting", MUTED)
		return
	end

	for row = 0, ROWS - 1 do
		local i = self.top + row
		local n = self.rows[i]
		if not n then break end

		local style = i == self.sel and SEL or (n.urgent and URGENT or ITEM)
		local y = row + 2
		g.fill(0, y, g.cols, 1, style)
		g.text(1, y, Text.clip(n.summary, g.cols - Grid.width(n.app) - 4), style)
		g.text(g.cols - Grid.width(n.app) - 1, y, n.app,
		       i == self.sel and style or MUTED)
	end

	local at = ROWS + 2
	g.text(0, at, ("─"):rep(g.cols), MUTED)

	local n = self.rows[self.sel]
	if not n then return end
	if n.body == "" then
		g.text(1, at + 1, "No body", MUTED)
	else
		for i, line in ipairs(wrap(n.body, g.cols - 2, BODY)) do
			g.text(1, at + i, line, ITEM)
		end
	end
	if n.exec ~= "" then
		g.text(1, at + BODY + 1, Text.clip("Return: " .. n.exec, g.cols - 2), MUTED)
	end
end

local cfg = config.load()
Surface.font(cfg.font, cfg.size)
Surface.border("round", TITLE)
Surface.layer("overlay")
Surface.anchor("top-right")
Surface.margin(cfg.gap, cfg.gap, 0, 0)
-- title, the list, a rule, the body, and a line for what Return would run
Surface.window(COLS, ROWS + BODY + 4)
Surface.listen(kipp.socket)
Surface.listen("theme")
Surface.run(panel)
