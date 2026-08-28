-- Drive surfaces/install.lua with no compositor and no wweft.
--
--   lua5.4 test/installer-surface.lua
--
-- wweft's script API is small and has three chokepoints: Surface.sh is the
-- only way out to the system, Surface.emit is the only way to stdout, and
-- onKey is the only way in. Stub those and the whole surface runs here, in
-- milliseconds, with every side effect recorded.
--
-- What this cannot check is how it looks. That needs eyes on a screen. What
-- it does check is the part a person cannot see by looking: that the answer
-- file says exactly what fig-install reads.

_G.FIG_INSTALL_TEST = true
package.path = "DE-shell/?.lua;" .. package.path

local calls, files, emitted, spawned, watched = {}, {}, {}, {}, {}
local grid_text = {}

-- What the fake machine answers. A test may replace any of these.
local SH = {
	["lsblk -dpno"] = "/dev/vda 20G disk\n/dev/sr0 1.9G rom\n/dev/sdb 931.5G disk Samsung SSD 860",
	["lsblk -no PKNAME"] = "sr0",
	["command -v fig-install"] = "/usr/bin/fig-install",
}

local function fake_sh(cmd)
	calls[#calls + 1] = cmd
	for k, v in pairs(SH) do
		if cmd:find(k, 1, true) then return v end
	end
	return ""
end

_G.Surface = {
	cellW = 8, cellH = 16, width = 0, height = 0, screenW = 1920, screenH = 1080,
	sh = function(cmd) return fake_sh(cmd) end,
	spawn = function(cmd) spawned[#spawned + 1] = cmd end,
	emit = function(t) emitted[#emitted + 1] = t end,
	watch = function(p) watched[#watched + 1] = p end,
	close = function(c) _G.CLOSED = c end,
	font = function() end, window = function() end, anchor = function() end,
	layer = function() end, border = function() end,
	-- Keep what run() was handed. Everything below dispatches through it the
	-- way wweft's C does, so the calling convention is under test too.
	run = function(t) _G.APP = t end,
	lines = function() return {} end,
}
-- Rows carry the style they were drawn with. Without that a selection can
-- move invisibly and every text check still passes, which is exactly what
-- happened: the surface used wweft's built-in Style.sel and Style.item, which
-- are not themed and paint alike, and nothing here noticed.
local grid_rows = {}
_G.Grid = {
	cols = 60, rows = 16,
	text = function(x, y, s, style)
		grid_text[#grid_text + 1] = s
		grid_rows[#grid_rows + 1] = {y = y, text = s, style = style}
	end,
	fill = function(x, y, w, h, style)
		grid_rows[#grid_rows + 1] = {y = y, fill = true, style = style}
	end,
	center = function(y, s, style)
		grid_text[#grid_text + 1] = s
		grid_rows[#grid_rows + 1] = {y = y, text = s, style = style}
	end,
	width = function(s) return #s end,
}
-- Style.define hands out a new id each time, as wweft does. Roles that ask
-- for different colours therefore get different ids, and a surface that drew
-- two roles with one id would show up here.
local next_id = 0
_G.Style = {define = function(fg, bg, id)
	if id then return id end
	next_id = next_id + 1
	return next_id
end}
_G.Text = {
	trim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end,
	chop = function(s) return s:sub(1, -2) end,
	clip = function(s, n) return s:sub(1, n) end,
	quote = function(s) return "'" .. s:gsub("'", "'\\''") .. "'" end,
	contains = function(a, b) return a:lower():find(b:lower(), 1, true) ~= nil end,
}
_G.Key = {text = ""}
_G.math.round = function(x) return math.floor(x + 0.5) end

-- io.open, so the answer file is captured rather than written. The surface
-- writes passphrases with io and not through a shell on purpose: a shell
-- command line is visible in ps to every user on the machine.
local real_open = io.open
io.open = function(path, mode)
	if mode ~= "w" then return real_open(path, mode) end
	local buf = {}
	return {
		write = function(_, s) buf[#buf + 1] = s end,
		close = function() files[path] = table.concat(buf) end,
	}
end

-- palette.load() reads the current theme off disk. Not this surface's job.
package.loaded["lib.palette"] = {
	load = function() return {} end,
	style = function(fg, bg, alpha, id) return Style.define(fg, bg, id) end,
}

local surface = dofile("DE-shell/surfaces/install.lua")

-- main() is what wweft runs. Calling it here means the harness exercises the
-- real startup, and Surface.run hands us the real callback table.
surface.main()
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

-- app.onKey(app, name), not onKey(name). wweft pushes the callback, inserts
-- the app table under it and calls it as a method. Getting this wrong is what
-- made every key silently do nothing while the panel still drew: the handler
-- bound `name` to the app table and matched nothing.
local function press(name, text)
	_G.Key.text = text or ""
	app.onKey(app, name)
end

local function type_text(s)
	for c in s:gmatch(".") do press(c, c) end
end

local function drawn()
	grid_text, grid_rows = {}, {}
	app.onDraw(app, _G.Grid)
	return table.concat(grid_text, "\n")
end

-- The style the row holding `text` was drawn with.
local function style_of(text)
	for _, r in ipairs(grid_rows) do
		if r.text and r.text:find(text, 1, true) then return r.style end
	end
end

-- ------------------------------------------------------------------- tests

check("the live image's own disk is not offered",
	not table.concat((function() local t = {} for _, d in ipairs(surface.S.disks) do
		t[#t + 1] = d.name end return t end)(), " "):find("sr0"),
	"disks were " .. #surface.S.disks)

check("both real disks are offered", #surface.S.disks == 2, #surface.S.disks)

local screen = drawn()
check("the first screen names the disks", screen:find("/dev/vda") and screen:find("20G"))

-- The check the first version did not have. A selection that moves without
-- changing anything on screen is the same as no selection at all.
local sel_style = style_of("/dev/vda")
local other_style = style_of("/dev/sdb")
check("the selected disk is drawn differently from the rest",
	sel_style ~= nil and sel_style ~= other_style,
	tostring(sel_style) .. " vs " .. tostring(other_style))
check("the branding is on the panel", screen:find("powered by omarchy"))

-- Called the way wweft calls it, a handler must still see the key name. A
-- handler written as onKey(name) binds name to the app table and matches
-- nothing, which draws perfectly and responds to no key at all.
check("a handler takes self before the key name",
	(function()
		local seen
		local saved = app.onKey
		app.onKey = function(selfarg, n) seen = n; return true end
		app.onKey(app, "Escape")
		app.onKey = saved
		return seen == "Escape"
	end)())

-- Walk the wizard the way a person would.
press("Down")                                        -- to /dev/sdb
check("Down moves the selection", surface.S.sel == 2, surface.S.sel)
drawn()
check("and the highlight moves with it",
	style_of("/dev/sdb") == sel_style and style_of("/dev/vda") == other_style,
	tostring(style_of("/dev/sdb")) .. " vs " .. tostring(style_of("/dev/vda")))
press("Up")                                          -- back to /dev/vda
check("Up moves it back", surface.S.sel == 1, surface.S.sel)
press("Return")
check("moved on to the passphrase", surface.S.step == 2, surface.S.step)

type_text("short")
press("Return")
type_text("short")
press("Return")
check("a short password is refused",
	surface.S.error ~= nil and surface.S.error:find("eight"), surface.S.error)

-- Back out and give it a real one.
press("Escape"); press("Escape")
surface.S.answers.pass, surface.S.answers.pass2 = nil, nil
surface.S.step = 2; surface.S.entry = ""
type_text("hunter2hunter2"); press("Return")
type_text("hunter2hunter3"); press("Return")
check("two that differ are refused",
	surface.S.error ~= nil and surface.S.error:find("not the same"), surface.S.error)

surface.S.entry = ""
surface.S.answers.pass2 = ""
type_text("hunter2hunter2")

-- While it is on screen, not after the step has moved on. Checked after the
-- fact this passed with the masking deleted, which made it decoration.
local typing = drawn()
check("a secret is masked while it is being typed",
	not typing:find("hunter2") and typing:find("%*%*%*%*"), typing:sub(1, 120))

press("Return")
check("matching passwords move on", surface.S.step == 4, surface.S.step)

local function retry_field(field, text)
	surface.S.entry = ""; surface.S.answers[field] = ""
	type_text(text); press("Return")
end

retry_field("user", "Paths")
check("an uppercase username is refused",
	surface.S.error ~= nil and surface.S.error:find("lowercase"), surface.S.error)
retry_field("user", "1paths")
check("a username starting with a digit is refused",
	surface.S.error ~= nil, surface.S.error)
retry_field("user", "")
check("an empty username is refused", surface.S.error ~= nil, surface.S.error)

-- The field stops taking characters at the length useradd stops accepting.
surface.S.entry = ""; surface.S.answers.user = ""
type_text(string.rep("a", 40))
check("a username cannot be typed past 32 characters",
	#surface.S.answers.user == 32, #surface.S.answers.user)

retry_field("user", "paths")
check("a good username moves on", surface.S.step == 5, surface.S.step)

retry_field("host", "-nope")
check("a hostname starting with a dash is refused",
	surface.S.error ~= nil, surface.S.error)
retry_field("host", "nope-")
check("a hostname ending with a dash is refused",
	surface.S.error ~= nil, surface.S.error)
retry_field("host", "think pad")
check("a hostname with a space is refused", surface.S.error ~= nil, surface.S.error)

surface.S.entry = ""; surface.S.answers.host = ""
type_text(string.rep("h", 70))
check("a hostname cannot be typed past 63 characters",
	#surface.S.answers.host == 63, #surface.S.answers.host)

retry_field("host", "thinkpad")
check("reached the confirmation", surface.S.step == 6, surface.S.step)

local confirm = drawn()
check("the confirmation names the disk and what happens",
	confirm:find("/dev/vda") and confirm:find("erased"), confirm:sub(1, 80))
check("the confirmation asks for the word", confirm:find("ERASE"))

press("Return")
check("a bare Return does not start an install",
	surface.S.error ~= nil and #spawned == 0, surface.S.error)

type_text("erase"); press("Return")
check("the wrong case does not start an install either",
	surface.S.error ~= nil and #spawned == 0, surface.S.error)

surface.S.entry = ""; surface.S.answers.erase = ""
type_text("ERASE")
check("what is typed here is not masked", drawn():find("ERASE"))

-- A machine with no installer on it. Opening the panel on a working desktop
-- to look at it should not be able to reach a disk.
SH["command -v fig-install"] = ""
press("Return")
check("no installer means nothing is spawned",
	#spawned == 0 and surface.S.error ~= nil, surface.S.error)
check("and it says so rather than looking like it worked",
	surface.S.error:find("Nothing was touched"), surface.S.error)
SH["command -v fig-install"] = "/usr/bin/fig-install"

surface.S.entry = ""; surface.S.answers.erase = ""
type_text("ERASE")
press("Return")   -- start the install

-- ------------------------------------------------- the contract with fig-install

local answers = files[surface.paths.answers]
check("an answer file was written", answers ~= nil)

if answers then
	local want = {
		FIG_MODE = "whole-disk",
		FIG_DISK = "/dev/vda",
		FIG_USER = "paths",
		FIG_HOSTNAME = "thinkpad",
		FIG_LUKS_PASS_FILE = surface.paths.key,
		FIG_USER_PASS_FILE = surface.paths.key,
		FIG_ROOT_PASS_FILE = surface.paths.key,
	}
	-- A leading newline so the first line needs no special case, and plain
	-- finds throughout: `-` is a quantifier in a Lua pattern, so "whole-disk"
	-- as a pattern does not mean what it looks like.
	local hay = "\n" .. answers
	for k, v in pairs(want) do
		check("answers say " .. k .. "=" .. v,
			hay:find("\n" .. k .. "=" .. v .. "\n", 1, true) ~= nil, answers)
	end
	check("no passphrase is in the answer file", not answers:find("hunter2"), answers)

	-- Every key the file sets must be one fig-install reads. A misspelt key is
	-- silently ignored by a shell `.`, so nothing else would ever catch it.
	local install = real_open("DE-shell/bin/fig-install"):read("a")
	for key in answers:gmatch("(FIG_[A-Z_]+)=") do
		check(key .. " is read by fig-install", install:find(key, 1, true) ~= nil)
	end
end

check("the password went to its own file, mode 600",
	files[surface.paths.key] == "hunter2hunter2", files[surface.paths.key])
-- Plain finds, counted by hand. gsub takes a pattern and the path holds
-- "fig-install", where `-` is a quantifier, so the pattern form counts zero.
local function occurrences(hay, needle)
	local n, at = 0, 1
	while true do
		local i = hay:find(needle, at, true)
		if not i then return n end
		n, at = n + 1, i + 1
	end
end
check("the disk, the login and root share one secret",
	answers and occurrences(answers, surface.paths.key) == 3,
	answers and occurrences(answers, surface.paths.key))

check("fig-install was spawned and not run through Surface.sh",
	#spawned == 1 and spawned[1]:find("fig%-install"), table.concat(spawned, "|"))
-- The invocation, not the name. The runtime directory is called fig-install
-- too, so every mkdir and chmod mentions it and a looser check passes always.
check("nothing ran fig-install on the 2s deadline",
	not table.concat(calls, "|"):find("fig-install --answers", 1, true))
check("the log is watched", watched[1] == surface.paths.log, table.concat(watched, "|"))

-- ------------------------------------------------------------ the log, and the end
SH["tail -n 200"] = "==> partitioning /dev/vda\n==> encrypting\nfig-install-rc=0"
app.onChange(app, surface.paths.log)
check("a finished install is noticed", surface.S.rc == 0, surface.S.rc)
check("the last screen says so", drawn():find("fig is installed"))

SH["tail -n 200"] = "==> partitioning /dev/vda\nfig-install: no package mirror\nfig-install-rc=1"
surface.S.rc = nil
app.onChange(app, surface.paths.log)
check("a failed install is noticed too", surface.S.rc == 1, surface.S.rc)
check("the last screen does not claim success", not drawn():find("fig is installed"))

print(("\n%d checks failed"):format(fails))
os.exit(fails == 0 and 0 or 1)
