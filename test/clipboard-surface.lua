-- Drive surfaces/clipboard.lua with no compositor, no wweft and no mpv.
--
--   lua5.4 test/clipboard-surface.lua
--
-- The preview has never been seen: mpv wants GL and the VM has none. So the
-- part that can be checked without a screen is what goes down the socket, and
-- that is the part that was wrong. One mpv is started with this surface and
-- quit with it; walking the cursor between pictures and text must never start
-- or kill another one.

package.path = "DE-shell/?.lua;" .. package.path

local spawned = {}

-- What the fake machine answers.
local SH = {
	["echo $PPID"] = "4242\n",
	["fig-clip list"] = table.concat({
		"text\tt1\thello world",
		"image\ti1\tshot.png",
		"text\tt2\tanother line",
		"image\ti2\tsecond.png",
	}, "\n"),
	["fig-clip path 'i1'"] = "/home/fig/.local/state/fig/clipboard/i1.png\n",
	["fig-clip path 'i2'"] = "/home/fig/.local/state/fig/clipboard/i2.png\n",
}

_G.Surface = {
	cellW = 8, cellH = 16, screenW = 1920, screenH = 1080,
	sh = function(cmd)
		for k, v in pairs(SH) do
			if cmd:find(k, 1, true) then return v end
		end
		return ""
	end,
	spawn = function(cmd) spawned[#spawned + 1] = cmd end,
	close = function(c) _G.CLOSED = c end,
	font = function() end, window = function() end, anchor = function() end,
	layer = function() end, border = function() end, margin = function() end,
	dismiss = function() end, every = function() end, listen = function() end,
	run = function(t) _G.APP = t end,
}
_G.Grid = {cols = 64, rows = 15, text = function() end, fill = function() end,
           width = function(s) return #s end}
local next_id = 0
_G.Style = {define = function(_, _, id)
	if id then return id end
	next_id = next_id + 1
	return next_id
end}
_G.Text = {
	chop = function(s) return s:sub(1, -2) end,
	clip = function(s, n) return s:sub(1, n) end,
	quote = function(s) return "'" .. s:gsub("'", "'\\''") .. "'" end,
	contains = function(a, b) return a:lower():find(b:lower(), 1, true) ~= nil end,
}
_G.Key = {text = ""}

package.loaded["lib.palette"] = {
	load = function() return {} end,
	style = function(fg, bg, alpha, id) return Style.define(fg, bg, id) end,
	changed = function() return false end,
}
package.loaded["lib.settings"] = {
	load = function() return {font = "", size = 16, gap = 8} end,
}

dofile("DE-shell/surfaces/clipboard.lua")

local app = _G.APP
if not app then print("FAIL Surface.run was never called"); os.exit(1) end

-- ------------------------------------------------------------------ helpers

local fails = 0
local function check(name, ok, detail)
	if ok then
		print("ok   " .. name)
	else
		fails = fails + 1
		print("FAIL " .. name .. (detail and ("  -- " .. tostring(detail)) or ""))
	end
end

-- app.onKey(app, name), not onKey(name). wweft inserts the app table under the
-- callback and calls it as a method.
local function press(name)
	_G.Key.text = ""
	app.onKey(app, name)
end

-- One tick is enough: the surface is driven at exactly the settle interval it
-- waits for.
local function tick() app.onTick(app) end

local mark = 0
local function since()
	local out = {}
	for i = mark + 1, #spawned do out[#out + 1] = spawned[i] end
	mark = #spawned
	return table.concat(out, "\n")
end

local function occurrences(hay, needle)
	local n, at = 0, 1
	while true do
		local i = hay:find(needle, at, true)
		if not i then return n end
		n, at = n + 1, i + 1
	end
end

local all = function() return table.concat(spawned, "\n") end

-- ------------------------------------------------------------------- startup

local started = since()
check("mpv is started with the surface", started:find("--wayland-app-id=fig-clip-preview", 1, true))
check("and it idles with a window, so a text row has something to be black in",
	started:find("--idle=yes", 1, true) and started:find("--force-window=yes", 1, true))
check("it is tied to this process, so an orphan cannot outlive the picker",
	started:find("kill -0 4242", 1, true))

-- The first row is text. Nothing to load, and nothing to unload either.
tick()
check("a text row on open sends nothing", since() == "", since())

-- ------------------------------------------------------------- walking the list

press("Down")   -- image i1
tick()
check("moving onto a picture loads it",
	since():find("loadfile", 1, true))
mark = #spawned

press("Down")   -- text t2
tick()
local off = since()
check("moving onto text unloads the picture", off:find('"stop"', 1, true), off)
-- This is the whole point of the change. mpv used to be quit here and started
-- again on the next picture, so the window blinked out from under the list.
check("and does not quit mpv", not off:find('"quit"', 1, true), off)

press("Down")   -- image i2
tick()
local back = since()
check("moving back onto a picture loads it again", back:find("loadfile", 1, true))
check("without starting a second mpv",
	not back:find("--wayland-app-id", 1, true), back)

press("Up")     -- text t2 again
tick()
mark = #spawned
press("Up")     -- image i1
press("Up")     -- text t1
tick()
check("text after text says nothing twice", occurrences(since(), '"stop"') <= 1, since())

check("one mpv for the whole walk",
	occurrences(all(), "--wayland-app-id=fig-clip-preview") == 1,
	occurrences(all(), "--wayland-app-id=fig-clip-preview"))
check("and it was never quit while the picker was up",
	not all():find('"quit"', 1, true))

-- --------------------------------------------------------------- the way out

mark = #spawned
press("Escape")
local bye = since()
check("Escape quits mpv", bye:find('"quit"', 1, true), bye)
check("and closes the surface", _G.CLOSED == 1, _G.CLOSED)

-- Return is the other exit, and it has to stop the preview too. A picker left
-- with an orphaned mpv on top of the screen is worse than no preview at all.
--
-- On a second surface, not this one. Escape has already quit mpv here, so
-- pressing Return next would find nothing to quit and pass for the wrong
-- reason.
_G.CLOSED, _G.APP = nil, nil
dofile("DE-shell/surfaces/clipboard.lua")
app = _G.APP
mark = #spawned
press("Return")
local picked = since()
check("Return puts the clip back", picked:find("fig%-clip put"), picked)
check("and quits mpv as well", picked:find('"quit"', 1, true), picked)
check("and closes the surface", _G.CLOSED == 0, _G.CLOSED)

print(("\n%d checks failed"):format(fails))
os.exit(fails == 0 and 0 or 1)
