-- Bluetooth. The adapter, and everything it knows about.
--
--   Bluetooth                    scanning  ‹ stop ›
--   soundcore AeroFit 2      72%  ‹ disconnect ›
--   Keyboard K380                 ‹ connect ›
--
--   Up/Down     move
--   Left/Right  choose what Return will do to the row you are on
--   Return      do it
--   Escape      close
--
-- kippsrv holds the bus, so this surface asks nothing and forks nothing: the
-- devices, their state and their battery all arrive as `bt` facts, and
-- CONNECT, DISCONNECT, FORGET and SCAN go back up the same socket. It stays
-- open while it works, because the fact coming back is the answer.
--
-- Two things do not fit through that socket. Powering the adapter, which bluez
-- will not do while rfkill holds a soft block, and pairing, which stops to ask
-- for a passkey. Both are `bt-actions`.
--
-- The height is fixed. A surface is sized once and the list does not exist
-- until the socket has answered, so there is nothing to size it by; the rows
-- scroll instead, which is also what a scan filling the list needs.

local kipp    = require("lib.kipp")
local palette = require("lib.palette")
local config  = require("lib.settings")

local HELPER = "bt-actions"

local COLS = 44
local LIST = 7           -- device rows. The adapter sits above them and stays

-- What each state can usefully be told, first choice first.
local RADIO_ACTS = {
	off      = {"turn on"},
	on       = {"scan", "turn off"},
	scanning = {"stop", "turn off"},
}
local DEVICE_ACTS = {
	connected = {"disconnect", "forget"},
	paired    = {"connect", "forget"},
	seen      = {"pair"},
}
local RANK = {connected = 1, paired = 2, seen = 3}

palette.load()
local TEXT = palette.style("foreground", "background", 0xf2)
local DIM  = palette.style("dark_foreground", "background", 0xf2)
local HEAD = palette.style("accent", "background", 0xf2)
local SEL  = palette.style("background", "accent")

local bt = {
	facts = kipp.store(),
	list  = {},          -- devices, connected first
	radio = nil,         -- the adapter's state, nil until it says
	at    = 1,           -- which of the adapter's actions is chosen
	sel   = 1,           -- 1 is the adapter, 2.. are devices
	top   = 1,
	moved = false,
}

function bt:acts()
	return RADIO_ACTS[self.radio or "off"] or {}
end

function bt:device(i)
	return self.list[i - 1]
end

function bt:build()
	-- Which verb each row was pointed at, so a battery arriving does not move
	-- the choice under the cursor.
	local was = {}
	for _, d in ipairs(self.list) do was[d.addr] = d.at end

	local rows = {}
	for f in self.facts:each("bt") do
		local state = f.attr.state or "seen"
		local name = f.attr.name
		rows[#rows + 1] = {
			addr    = f.subj[1],
			name    = (name and name ~= "") and name or f.subj[1],
			state   = state,
			battery = f.attr.battery or "",
			acts    = DEVICE_ACTS[state] or DEVICE_ACTS.seen,
			at      = 1,
		}
	end

	table.sort(rows, function(a, b)
		local ra, rb = RANK[a.state] or 9, RANK[b.state] or 9
		if ra ~= rb then return ra < rb end
		return a.name:lower() < b.name:lower()
	end)

	for _, d in ipairs(rows) do
		local at = was[d.addr]
		if at and at <= #d.acts then d.at = at end
	end
	self.list = rows

	-- The list is empty when this opens, so the first devices to arrive are
	-- what it was opened for. After a key press the cursor is the person's.
	if not self.moved and #rows > 0 then self.sel = 2 end
	self.sel = math.max(1, math.min(1 + #rows, self.sel))
	self:scroll()
end

function bt:scroll()
	local want = math.max(1, self.sel - 1)
	self.top = math.max(want - LIST + 1, math.min(self.top, want))
end

function bt:move(by)
	self.moved = true
	self.sel = math.max(1, math.min(1 + #self.list, self.sel + by))
	self:scroll()
end

function bt:step(by)
	local d = self:device(self.sel)
	if d then
		d.at = (d.at - 1 + by) % #d.acts + 1
	elseif #self:acts() > 0 then
		self.at = (self.at - 1 + by) % #self:acts() + 1
	end
end

function bt:fire()
	local d = self:device(self.sel)

	if not d then
		local act = self:acts()[self.at]
		if act == "turn on" or act == "turn off" then
			Surface.spawn(("%s power %s"):format(HELPER, act == "turn on" and "on" or "off"))
		elseif act == "scan" then
			kipp.send("SCAN\ton")
		elseif act == "stop" then
			kipp.send("SCAN\toff")
		end
		return
	end

	local act = d.acts[d.at]
	if act == "pair" then
		Surface.spawn(("%s pair %s"):format(HELPER, Text.quote(d.addr)))
	else
		kipp.send(act:upper() .. "\t" .. d.addr)
	end
end

function bt:onKey(k)
	if k == "Down" or k == "j" then
		self:move(1)
	elseif k == "Up" or k == "k" then
		self:move(-1)
	elseif k == "Left" or k == "h" then
		self:step(-1)
	elseif k == "Right" or k == "l" then
		self:step(1)
	elseif k == "Return" or k == "space" then
		self:fire()
	elseif k == "Escape" then
		Surface.close(0)
	else
		return false
	end
	return true
end

function bt:onMessage(line)
	if palette.changed(line) then return end

	local kind = self.facts:feed(line)
	if kind == "bt" then
		self:build()
	elseif kind == "bt_radio" then
		-- One adapter is the common machine and the first is as good a choice
		-- as any on the others.
		for f in self.facts:each("bt_radio") do
			if f.attr.state ~= self.radio then self.radio, self.at = f.attr.state, 1 end
			break
		end
	end
end

-- One shape for both kinds of row: what it is, one fact about it, and what
-- Return would do.
function bt:draw_row(g, y, name, note, acts, at, sel, style, label)
	local act = #acts > 0 and ("‹ %s ›"):format(acts[at]) or ""
	local x = g.cols - Grid.width(act) - 1

	g.fill(0, y, g.cols, 1, style)
	g.text(1, y, Text.clip(name, x - Grid.width(note) - 3), label or style)
	if note ~= "" then
		g.text(x - Grid.width(note) - 1, y, note, sel and style or DIM)
	end
	g.text(x, y, act, sel and style or DIM)
end

function bt:onDraw(g)
	g.fill(0, 0, g.cols, g.rows, TEXT)

	local on = self.sel == 1
	self:draw_row(g, 0, "Bluetooth", self.radio or "no adapter",
	              self:acts(), self.at, on, on and SEL or TEXT, not on and HEAD or nil)

	if #self.list == 0 then
		g.text(1, 1, self.radio == "off" and "The radio is off" or "Nothing yet", DIM)
		return
	end

	for line = 0, LIST - 1 do
		local i = self.top + line
		local d = self.list[i]
		if not d then break end

		local sel = self.sel == i + 1
		self:draw_row(g, 1 + line, d.name,
		              d.battery ~= "" and (d.battery .. "%") or "",
		              d.acts, d.at, sel, sel and SEL or TEXT)
	end

	if self.top > 1 then g.text(g.cols - 1, 1, "▴", DIM) end
	if self.top + LIST - 1 < #self.list then g.text(g.cols - 1, LIST, "▾", DIM) end
end

local cfg = config.load()
Surface.font(cfg.font, cfg.size)
Surface.border("round", HEAD)
Surface.layer("overlay")
Surface.anchor("top-right")
Surface.margin(cfg.gap, cfg.gap, 0, 0)
Surface.window(COLS, 1 + LIST)
Surface.listen(kipp.socket)
Surface.listen("theme")
Surface.run(bt)
