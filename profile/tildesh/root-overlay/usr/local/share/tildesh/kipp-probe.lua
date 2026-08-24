-- Everything kippsrv says, on a surface. `test-wweft` runs it.
--
-- This is a debug panel, not the bar. It knows no kind by name: it takes each
-- line apart the way kipp says to, which is the kind first, then the subject
-- fields, then the attributes from the first field holding an `=`. So a fact
-- that no adapter has written yet still shows up the day one does.
--
-- It is also the proof that wweft needs nothing new to read kippsrv:
-- Surface.listen on a path connects to that socket, and onMessage gets a line.

local RAW_KEEP = 6

-- Columns. A kind is short, a subject can be a 36 character UUID, and the
-- attributes take what is left. Every field is cut to its own width: drawing
-- a long one and letting the next column paint over it reads as a value that
-- ends where it does not. Text.clip and not string.sub, because a column is
-- not a byte.
local KIND_X, KIND_W = 1, 10
local SUBJ_X, SUBJ_W = 12, 38
local ATTR_X = 51

-- Palette. Four numbers, 0xAARRGGBB.
local FG = 0xffcfd4da
local BG = 0xff15181c
local ACCENT = 0xff7fbfff
local DIM = 0xff6b7078

local BASE = Style.define(FG, BG)
local HEAD = Style.define(BG, ACCENT)
local KIND = Style.define(ACCENT, BG)
local SUBJ = Style.define(FG, BG)
local ATTR = Style.define(DIM, BG)

local probe = {
	order = {},          -- fact keys, in the order they first arrived
	facts = {},          -- key -> {kind, subject, attrs}
	raw = {},
	count = 0,
	showRaw = true,
}

-- kind, then subject fields, then attributes. The first field holding an `=`
-- starts the attributes, and only the first `=` in it separates a name from a
-- value, so `name=home=wifi` is one attribute.
--
-- The trailing tab is what makes `(.-)\t` see the last field. A pattern of
-- `[^\t]*` would match an empty string between every pair and repeat itself.
function probe:onMessage(line)
	self.count = self.count + 1

	self.raw[#self.raw + 1] = line
	while #self.raw > RAW_KEEP do table.remove(self.raw, 1) end

	local kind, subject, attrs = nil, {}, {}
	for field in (line .. "\t"):gmatch("(.-)\t") do
		if not kind then
			kind = field
		else
			if #attrs == 0 and not field:find("=", 1, true) then
				subject[#subject + 1] = field
			else
				attrs[#attrs + 1] = field
			end
		end
	end
	if not kind then return end

	subject = table.concat(subject, " ")
	local key = kind .. "\t" .. subject
	if not self.facts[key] then self.order[#self.order + 1] = key end
	self.facts[key] = { kind = kind, subject = subject, attrs = table.concat(attrs, " ") }
end

function probe:onKey(name)
	if name == "q" or name == "Escape" then
		Surface.close(0)
	elseif name == "c" then
		self.order, self.facts, self.raw = {}, {}, {}
	elseif name == "r" then
		self.showRaw = not self.showRaw
	else
		return false
	end
	return true
end

function probe:onDraw(g)
	g.fill(0, 0, g.cols, g.rows, BASE)

	g.fill(0, 0, g.cols, 1, HEAD)
	g.text(0, 0, (" kipp  %d lines  %s"):format(self.count, self.socket), HEAD)

	local y = 2
	local last = self.showRaw and g.rows - RAW_KEEP - 2 or g.rows
	for _, key in ipairs(self.order) do
		if y >= last then break end
		local f = self.facts[key]
		g.text(KIND_X, y, Text.clip(f.kind, KIND_W), KIND)
		g.text(SUBJ_X, y, Text.clip(f.subject, SUBJ_W), SUBJ)
		g.text(ATTR_X, y, Text.clip(f.attrs, g.cols - ATTR_X - 1), ATTR)
		y = y + 1
	end

	if #self.order == 0 then
		g.text(1, 2, "nothing yet. Is kippsrv running?", ATTR)
	end

	if not self.showRaw then return end

	local ry = g.rows - RAW_KEEP - 1
	g.text(1, ry, "raw  (q quit, c clear, r hide)", ATTR)
	for i, line in ipairs(self.raw) do
		g.text(1, ry + i, Text.clip((line:gsub("\t", " ")), g.cols - 2), ATTR)
	end
end

probe.socket = arg[1] or ((os.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/kippsrv.sock")

Surface.font("", 15)
Surface.layer("overlay")
Surface.anchor("center")
Surface.border("round")
Surface.dismiss(false)
Surface.window(100, 26)
Surface.listen(probe.socket)
Surface.run(probe)
