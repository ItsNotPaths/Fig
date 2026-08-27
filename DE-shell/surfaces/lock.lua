-- The lock screen.
--
--   type        the password. Every character draws as an asterisk
--   Backspace   one back
--   Escape      clear what has been typed
--   Return      check it. Right unlocks, wrong clears and says so
--
-- Not a layer surface. Surface.lock() takes the ext-session-lock role, so the
-- compositor blanks every output the moment this starts and keeps them blank
-- until Surface.unlock() is called. Nothing else can open the session, and
-- that includes this process dying: a crash leaves the machine locked, which
-- is the right way round.
--
-- The surface is the whole output, so the field below is drawn in the middle
-- of it rather than being a small surface that is centred. The field is a
-- fixed width with the asterisks centred inside it, so it grows both ways
-- from the middle instead of running to the right.

local palette = require("lib.palette")
local config  = require("lib.settings")

local FIELD = 96           -- cells inside the field
local DOT   = "*"

local pw     = ""
local failed = false

local cfg = config.load()
Surface.font(cfg.font, cfg.size)

Surface.lock()
Surface.window(0, 0)       -- the compositor decides, and it says the output
Surface.keyboard(true)
Surface.dismiss(false)     -- there is nothing here to lose the focus to

palette.load()
local BASE  = palette.style("foreground", "background", nil, Style.base)
local FIELD_STYLE = palette.style("foreground", "lighter_background")
local LABEL = palette.style("muted", "background")
local WRONG = palette.style("red", "background")

local lock = {}

function lock:onDraw(g)
	-- FIELD is what it wants. A narrow output gets what there is.
	local w = FIELD < g.cols - 2 and FIELD or g.cols - 2
	local x = (g.cols - w) // 2
	local y = g.rows // 2

	g.fill(0, 0, g.cols, g.rows, BASE)

	local title = failed and "Wrong password" or "Locked"
	g.text((g.cols - g.width(title)) // 2, y - 2, title,
	       failed and WRONG or LABEL)

	-- One row, and always w wide, so the field does not move as the
	-- password grows. Only what is inside it changes.
	g.fill(x, y, w, 1, FIELD_STYLE)

	local n = #pw > w - 2 and w - 2 or #pw
	g.text(x + (w - n) // 2, y, string.rep(DOT, n), FIELD_STYLE)
end

local function submit()
	if pw == "" then return end

	-- The password goes down the child's stdin. A command line and the
	-- environment are both readable in /proc by anything else this user
	-- runs. stdin is not.
	local _, rc = Surface.sh("fig-auth", 10000, pw)
	pw = ""
	if rc == 0 then
		Surface.unlock(0)
	else
		failed = true
	end
end

function lock:onKey(k)
	if k == "Return" or k == "KP_Enter" then
		submit()
	elseif k == "BackSpace" then
		pw = pw:sub(1, -2)
		failed = false
	elseif k == "Escape" then
		pw = ""
		failed = false
	else
		-- Only what a key actually typed. A modifier or an arrow
		-- types nothing and must not become a character.
		local t = Key.text
		if t ~= "" and t:byte(1) >= 0x20 then
			pw = pw .. t
			failed = false
		end
	end
	return true
end

Surface.run(lock)
