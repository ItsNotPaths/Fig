-- Put fig on a disk.
--
--   Up/Down     move            Return    next
--   Escape      back, or quit on the first step
--
-- This surface collects answers and watches a log. It cannot partition
-- anything and does not know how: `fig-install` does the work, reads the
-- answer file this writes, and is the same program whether a person or a
-- test drove it. Every risky decision lives there, behind its own refusals.
--
-- fig, powered by omarchy.

local palette = require("lib.palette")

local COLS, ROWS = 62, 18
local RUNDIR = (os.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/fig-install"
local ANSWERS, KEYFILE = RUNDIR .. "/answers", RUNDIR .. "/key"
local LOG = RUNDIR .. "/log"

-- The steps, in order. `field` is what the answer is called; a step with no
-- field draws something other than a question.
local STEPS = {
	{id = "disk",     title = "Which disk?",           list = true},
	{id = "pass",     title = "Password",              field = "pass", secret = true,
	 note = "unlocks the disk, and logs you in"},
	{id = "pass2",    title = "Again",                 field = "pass2", secret = true},
	{id = "user",     title = "Your username",         field = "user"},
	{id = "host",     title = "Name for this machine", field = "host"},
	{id = "confirm",  title = "Ready", field = "erase"},
	{id = "running",  title = "Installing"},
	{id = "done",     title = ""},
}

-- How much a field will take. The lengths are the system's: useradd stops at
-- 32 and a hostname label at 63, so a longer answer would fail at the far end
-- of a fifteen minute install rather than here.
local LIMITS = {pass = 128, pass2 = 128, user = 32, host = 63, erase = 8}

local S = {step = 1, answers = {user = "fig", host = "fig"}, entry = "",
           disks = {}, sel = 1, error = nil, log = {}, rc = nil}

-- Roles, not colours, and our own ids. wweft ships St.base and friends but
-- they are not themed and several of them paint the same, so a selected row
-- drawn in St.sel next to St.item is a selection nobody can see. Every
-- other fig surface builds its own through palette.style; so does this one.
local St = {}
local function styles()
	St.base  = palette.style("foreground", "background", 0xf2, 0)
	St.title = palette.style("accent", "background", 0xf2)
	St.item  = palette.style("foreground", "background", 0xf2)
	St.sel   = palette.style("background", "accent")
	St.dim   = palette.style("dark_foreground", "background", 0xf2)
	St.warn  = palette.style("red", "background", 0xf2)
end

local function step() return STEPS[S.step] end

-- Whole disks only, and never the one the live image is running from. The
-- refusal is fig-install's too; this one is so the disk is not offered.
local function find_disks()
	local out = Surface.sh("lsblk -dpno NAME,SIZE,TYPE,MODEL 2>/dev/null", 4000)
	local boot = Surface.sh("lsblk -no PKNAME $(findmnt -no SOURCE /run/artix/bootmnt "
		.. "2>/dev/null) 2>/dev/null | head -1", 4000)
	boot = Text.trim(boot or "")
	local rows = {}
	for line in (out or ""):gmatch("[^\n]+") do
		local name, size, kind = line:match("^(%S+)%s+(%S+)%s+(%S+)")
		local skip = kind ~= "disk"
			or name:match("^/dev/zram%d")            -- RAM, not a disk
			or (boot ~= "" and name:find(boot, 1, true))
		if not skip then
			local model = Text.trim(line:match("^%S+%s+%S+%s+%S+%s*(.*)$") or "")
			rows[#rows + 1] = {name = name, size = size, model = model}
		end
	end
	return rows
end

local function write_file(path, text, mode)
	local f = io.open(path, "w")
	if not f then return false end
	f:write(text)
	f:close()
	if mode then Surface.sh("chmod " .. mode .. " " .. Text.quote(path), 2000) end
	return true
end

-- The contract with fig-install, and the only place it is written. A key that
-- fig-install does not read is a key nobody will notice is misspelt.
local function write_answers()
	Surface.sh("mkdir -p " .. Text.quote(RUNDIR) .. " && chmod 700 " .. Text.quote(RUNDIR), 2000)
	if not write_file(KEYFILE, S.answers.pass, "600") then return "cannot write the key file" end
	local body = table.concat({
		"FIG_MODE=whole-disk",
		"FIG_DISK=" .. S.answers.disk,
		-- The same file three times. fig-install keeps the three apart so an
		-- answer file written by hand can use three different secrets; this
		-- surface does not offer that, because nobody wants to be asked twice.
		"FIG_LUKS_PASS_FILE=" .. KEYFILE,
		"FIG_USER=" .. S.answers.user,
		"FIG_USER_PASS_FILE=" .. KEYFILE,
		"FIG_ROOT_PASS_FILE=" .. KEYFILE,
		"FIG_HOSTNAME=" .. S.answers.host,
	}, "\n") .. "\n"
	if not write_file(ANSWERS, body, "600") then return "cannot write the answer file" end
	return nil
end

-- Never Surface.sh: that has a deadline measured in seconds and this takes
-- fifteen minutes. Spawn it, then read the log it writes.
local function start_install()
	-- Nothing on a machine that has no installer. This surface reads real
	-- disks and lists them, so it is worth opening on a working desktop to
	-- look at; that is only safe if the last key cannot reach a disk.
	if Text.trim(Surface.sh("command -v fig-install 2>/dev/null", 2000) or "") == "" then
		S.error = "no fig-install on this machine. Nothing was touched."
		S.step = S.step - 1
		return
	end
	local err = write_answers()
	if err then S.error = err; return end
	write_file(LOG, "")
	Surface.spawn("sh -c " .. Text.quote(
		"sudo -n fig-install --answers " .. ANSWERS .. " --yes >" .. LOG .. " 2>&1; "
		.. "echo \"fig-install-rc=$?\" >>" .. LOG))
	Surface.watch(LOG)
end

local function validate()
	local s, a = step(), S.answers
	if s.id == "disk" then
		if not S.disks[S.sel] then return "no disk to install to" end
		a.disk = S.disks[S.sel].name

	elseif s.id == "pass2" then
		if a.pass ~= a.pass2 then return "the two are not the same" end
		if #(a.pass or "") < 8 then return "at least eight characters" end

	elseif s.id == "user" then
		if #(a.user or "") == 0 then return "a name is needed" end
		if #a.user > 32 then return "at most 32 characters" end
		if not a.user:match("^[a-z_][a-z0-9_-]*$") then
			return "lowercase, starting with a letter or underscore"
		end

	elseif s.id == "host" then
		if #(a.host or "") == 0 then return "a name is needed" end
		if #a.host > 63 then return "at most 63 characters" end
		-- A label may not start or end with a dash. Every resolver on the
		-- network applies that rule, so it is not one we are inventing.
		if not a.host:match("^[a-zA-Z0-9][a-zA-Z0-9-]*$") or a.host:sub(-1) == "-" then
			return "letters, digits and dashes, not at either end"
		end

	elseif s.id == "confirm" then
		-- The surface passes --yes, so fig-install will not ask again. This
		-- is the only place anybody is told what is about to happen, which
		-- makes a bare Return the wrong key for it.
		if a.erase ~= "ERASE" then return "type ERASE, in capitals" end
	end
	return nil
end

local function advance()
	S.error = validate()
	if S.error then return end
	S.step = S.step + 1
	S.entry = ""
	local s = step()
	if s and s.field then S.entry = S.answers[s.field] or "" end
	if s and s.id == "running" then start_install() end
end

-- ------------------------------------------------------------------ draw

local function draw_list(g)
	for i, d in ipairs(S.disks) do
		local y = 3 + i - 1
		if y < Grid.rows - 3 then
			local style = i == S.sel and St.sel or St.item
			Grid.fill(0, y, Grid.cols, 1, style)
			Grid.text(2, y, Text.clip(d.name .. "  " .. d.size
				.. (d.model ~= "" and ("  " .. d.model) or ""), Grid.cols - 4), style)
		end
	end
	if #S.disks == 0 then
		Grid.text(2, 3, "No disk found that is not the live image.", St.dim)
	end
end

local function draw_confirm(g)
	local a = S.answers
	local lines = {
		"disk       " .. (a.disk or "?"),
		"layout     GPT, 1G EFI, LUKS2, btrfs",
		"subvolumes @ @home @snapshots @log @pkg",
		"user       " .. a.user,
		"hostname   " .. a.host,
		"",
		"Everything on " .. (a.disk or "?") .. " is erased.",
	}
	for i, l in ipairs(lines) do Grid.text(2, 2 + i, l, St.item) end
	Grid.text(2, Grid.rows - 4, "Type ERASE to install.  Escape goes back.", St.dim)
	Grid.text(2, Grid.rows - 3, "> " .. S.entry .. "_", St.item)
end

local function draw_running(g)
	local first = math.max(1, #S.log - (Grid.rows - 6))
	local y = 2
	for i = first, #S.log do
		Grid.text(2, y, Text.clip(S.log[i], Grid.cols - 4), St.dim)
		y = y + 1
	end
end

local function draw_done(g)
	if S.rc == 0 then
		Grid.center(3, "fig is installed.", St.title)
		Grid.center(5, "Remove the image and restart.", St.item)
	else
		Grid.center(3, "The install did not finish.", St.title)
		Grid.center(5, "fig-install exited " .. tostring(S.rc), St.item)
		Grid.center(7, LOG, St.dim)
	end
	Grid.center(Grid.rows - 2, "Escape closes this.", St.dim)
end

-- self first: wweft dispatches these as methods, `onDraw(app, Grid)`.
local function onDraw(_, g)
	local s = step()
	Grid.fill(0, 0, Grid.cols, Grid.rows, St.base)
	Grid.center(0, "fig", St.title)
	Grid.center(1, "powered by omarchy", St.dim)

	if s.id == "done" then draw_done(g); return end
	Grid.text(2, 2, s.title, St.title)

	if s.list then
		draw_list(g)
	elseif s.id == "confirm" then
		draw_confirm(g)
	elseif s.id == "running" then
		draw_running(g)
	elseif s.field then
		local shown = s.secret and string.rep("*", #S.entry) or S.entry
		Grid.text(2, 4, "> " .. shown .. "_", St.item)
		if s.note then Grid.text(2, 6, s.note, St.dim) end
	end

	if S.error then Grid.text(2, Grid.rows - 2, S.error, St.warn) end
end

-- ------------------------------------------------------------------- key

local function onKey(_, name)
	local s = step()
	if s.id == "running" then return true end          -- nothing to press
	if s.id == "done" then
		if name == "Escape" or name == "Return" then Surface.close(S.rc or 0) end
		return true
	end

	if name == "Escape" then
		if S.step == 1 then Surface.close(1) end
		S.step = math.max(1, S.step - 1)
		S.error = nil
		local p = step()
		S.entry = p.field and (S.answers[p.field] or "") or ""
		return true
	end
	if name == "Return" then advance(); return true end

	if s.list then
		if name == "Down" then S.sel = math.min(#S.disks, S.sel + 1)
		elseif name == "Up" then S.sel = math.max(1, S.sel - 1) end
		return true
	end
	if s.field then
		if name == "BackSpace" then
			S.entry = Text.chop(S.entry)
		elseif Key.text ~= "" and #S.entry < (LIMITS[s.field] or 64) then
			S.entry = S.entry .. Key.text
		end
		S.answers[s.field] = S.entry
		S.error = nil
		return true
	end
	return false
end

-- fig-install writes its log a line at a time, so every change is new tail.
local function onChange(_, path)
	local out = Surface.sh("tail -n 200 " .. Text.quote(path), 3000) or ""
	S.log = {}
	for line in out:gmatch("[^\n]+") do
		local rc = line:match("^fig%-install%-rc=(%d+)$")
		if rc then
			S.rc = tonumber(rc)
			S.step = #STEPS                       -- the done step
		else
			S.log[#S.log + 1] = line
		end
	end
	return true
end

-- --------------------------------------------------------------- startup

local function main()
	palette.load()
	styles()
	S.disks = find_disks()
	Surface.font("", 16)
	Surface.window(COLS, ROWS)
	Surface.anchor("center")
	Surface.layer("overlay")
	Surface.border("round")
	Surface.run{onDraw = onDraw, onKey = onKey, onChange = onChange}
end

-- The harness loads this file for its parts and drives them itself, so the
-- surface is only raised when something actually ran the script.
if not _G.FIG_INSTALL_TEST then main() end

return {S = S, STEPS = STEPS, onKey = onKey, onDraw = onDraw, onChange = onChange,
        styles = styles, main = main,
        find_disks = find_disks, write_answers = write_answers, advance = advance,
        paths = {answers = ANSWERS, key = KEYFILE, log = LOG}}
