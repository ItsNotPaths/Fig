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
-- The list and the filtering are lib/picker.lua. The body of whatever is
-- selected fills the box underneath, which is the footer the picker leaves
-- room for. Return is left for running the thing rather than expanding it,
-- because a notification worth opening is worth opening in one press.
--
--   type        filter, on the summary and the app
--   Up/Down     move
--   Return      run `exec`, if the notification carries one
--   Delete      dismiss it
--   Escape      close

local picker  = require("lib.picker")
local kipp    = require("lib.kipp")
local palette = require("lib.palette")
local config  = require("lib.settings")

local COLS = 52
local ROWS = 10       -- the list
local BODY = 4        -- the box under it

-- Break a line to fit, on spaces where there is one and mid-word where there
-- is not, because a path with no spaces in it still has to be readable.
local function wrap(text, cols, lines)
	local out, rest = {}, text
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
	return out
end

local facts = kipp.store()
local said = false

-- palette.style and not Style.define: it records the role, so the colour
-- follows a theme change like every other one on this surface.
local URGENT = palette.style("red", "background", 0xf2)

-- Newest last, which is the order kippsrv sent them in, so a list that grows
-- while it is open does not move what is under the cursor.
local function notifs()
	local rows = {}
	for f in facts:each("notif") do
		rows[#rows + 1] = {
			text   = f.attr.summary or "",
			note   = f.attr.app or "",
			search = f.attr.app or "",
			style  = f.attr.urgency == "critical" and URGENT or nil,
			value  = {id = f.subj[1], body = f.attr.body or "",
			          exec = f.attr.exec or ""},
		}
	end
	return rows
end

-- Uppercase, up the socket kippsrv is already listening on. The fact
-- disappearing is what takes the row away, so nothing is removed here.
--
-- A tab. kipp separates the kind from its subject with one, and a space makes
-- the whole line one field that no adapter claims.
local function say(word, row)
	if row then kipp.send(word .. "\t" .. row.value.id) end
end

local list = picker.new{
	prompt  = "Notifications",
	rows    = ROWS,
	sources = {{name = "notif", rows = notifs}},

	pick = function(row)
		if row.value.exec == "" then return end
		Surface.spawn(row.value.exec)
		say("NOTIFY-CLOSE", row)
		Surface.close(0)
	end,

	key = function(k, self)
		if k == "Delete" or k == "BackSpace" then
			say("NOTIFY-CLOSE", self:selected())
		elseif k == "Escape" then
			Surface.close(1)
		else
			return false
		end
		return true
	end,
}
list.empty = "Nothing waiting"

function list:onMessage(line)
	if palette.changed(line) then return end
	-- Every fact is read, and only ours changes the list. Marking them read is
	-- kippsrv's to record, so that a second surface sees the same thing.
	if facts:feed(line) ~= "notif" then return end
	self:refresh()

	-- Opening the panel is what reading is, and it is said once. kippsrv
	-- republishes each fact with read=1, which arrives here as another notif
	-- line: saying it again for those would never stop.
	if not said and #self.hits > 0 then
		said = true
		kipp.send("NOTIFY-READ")
	end
end

-- The picker draws the prompt and the list. Everything below the rule is the
-- selected notification, and is this file's.
local draw = list.onDraw
function list:onDraw(g)
	draw(self, g)

	local at = ROWS + 1
	g.text(0, at, ("─"):rep(g.cols), self.style.dim)

	local row = self:selected()
	if not row then return end

	if row.value.body == "" then
		g.text(1, at + 1, "No body", self.style.dim)
	else
		for i, text in ipairs(wrap(row.value.body, g.cols - 2, BODY)) do
			g.text(1, at + i, text, self.style.item)
		end
	end
	if row.value.exec ~= "" then
		g.text(1, at + BODY + 1,
		       Text.clip("Return: " .. row.value.exec, g.cols - 2), self.style.dim)
	end
end

local cfg = config.load()
Surface.font(cfg.font, cfg.size)
Surface.border("round", list.style.title)
Surface.layer("overlay")
Surface.anchor("top-right")
Surface.margin(cfg.gap, cfg.gap, 0, 0)
-- the query line, the list, a rule, the body, and what Return would run
Surface.window(COLS, ROWS + BODY + 3)
Surface.listen(kipp.socket)
Surface.listen("theme")
Surface.run(list)
