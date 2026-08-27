-- What has been copied. Pick one and it is the clipboard again.
--
--   type        filter
--   Up/Down     move
--   Return      make it the clipboard and close
--   Escape      close
--
-- The history is files, written by `fig-clip watch`, which hedl starts
-- with the session. This surface only reads them.
--
-- A picture cannot be drawn here: wweft is a grid of glyphs and has no image
-- decoder, and giving it one to preview a clipboard entry is the wrong place
-- to put a decoder. So the preview is mpv, floated under this window by a
-- hedl rule, and moved from clip to clip over its own IPC socket rather than
-- being started again for every arrow key.
--
-- It never takes the keyboard away. hedl leaves the keyboard with a layer
-- surface on `overlay` while one is up, so a window mapping under it changes
-- nothing about where the keys go.
--
-- The preview is tied to this process twice over, because an orphaned mpv on
-- top of the screen is worse than no preview: Escape and Return both stop it,
-- and the shell that starts it also watches this pid and kills it if this
-- surface goes away without saying so.

local picker  = require("lib.picker")
local palette = require("lib.palette")
local config  = require("lib.settings")

local COLS, ROWS = 64, 14
local SETTLE = 120     -- ms of stillness before the preview follows

local TEXT_GLYPH  = "󰈙"
local IMAGE_GLYPH = "󰋩"

local RUN = os.getenv("XDG_RUNTIME_DIR") or "/tmp"
local SOCK = RUN .. "/fig/clip-preview.sock"

-- Surface.sh does not double fork, so the shell's parent is this process.
-- Surface.spawn does, so asking there would answer 1.
local ME = Surface.sh("echo $PPID", 1000):gsub("%s+$", "")

palette.load()
local NOTE = palette.style("dark_foreground", "background")

-- The preview process. One mpv, kept for as long as images are being walked
-- through, told what to show down its socket.
local mpv = {up = false, showing = nil, want = nil, due = nil}

function mpv:start()
	if self.up then return end
	self.up = true
	-- --wayland-app-id is what the hedl rule matches, so this window is
	-- floated and placed and an mpv somebody opened to watch something is
	-- left alone.
	Surface.spawn((
		"mkdir -p %s; " ..
		"mpv --wayland-app-id=fig-clip-preview --input-ipc-server=%s " ..
		"--idle=yes --force-window=yes --osc=no --no-input-default-bindings " ..
		"--image-display-duration=inf --keep-open=yes --really-quiet " ..
		">/dev/null 2>&1 & m=$!; " ..
		"while kill -0 %s 2>/dev/null; do sleep 0.5; done; kill $m 2>/dev/null")
		:format(Text.quote(RUN .. "/fig"), Text.quote(SOCK), ME))
end

function mpv:send(json)
	Surface.spawn(("printf %s | socat -t1 - UNIX-CONNECT:%s >/dev/null 2>&1")
	              :format(Text.quote(json .. "\n"), Text.quote(SOCK)))
end

function mpv:show(id, path)
	self:start()
	self.showing = id
	self:send(('{"command":["loadfile","%s"]}'):format(path))
end

function mpv:stop()
	if not self.up then return end
	self.up, self.showing = false, nil
	self:send('{"command":["quit"]}')
end

-- What the selection wants, applied on a tick rather than on the key. Holding
-- Down through twenty rows is then one loadfile and not twenty.
--
-- An id and not a path, because turning one into the other is a fork and the
-- whole point of waiting is to not do that per key press.
function mpv:aim(id)
	self.want = id
	self.due = SETTLE
end

function mpv:tick(ms)
	if not self.due then return end
	self.due = self.due - ms
	if self.due > 0 then return end
	self.due = nil

	if not self.want then
		self:stop()
		return
	end
	if self.want == self.showing then return end

	local path = Surface.sh("fig-clip path " .. Text.quote(self.want), 1000)
	              :gsub("%s+$", "")
	if path ~= "" then self:show(self.want, path) end
end

local function clips()
	local out = {}
	for line in Surface.sh("fig-clip list", 3000):gmatch("[^\n]+") do
		local kind, id, what = line:match("^(%a+)\t(%S+)\t(.*)$")
		if kind then
			out[#out + 1] = {
				text  = ("%s %s"):format(kind == "image" and IMAGE_GLYPH or TEXT_GLYPH, what),
				value = {kind = kind, id = id},
			}
		end
	end
	return out
end

local list = picker.new{
	prompt  = "Clipboard",
	rows    = ROWS,
	sources = {{name = "clips", rows = clips}},

	-- Only a picture is worth a window. Text is already on screen, in the row
	-- the cursor is on.
	moved = function(row)
		mpv:aim(row and row.value.kind == "image" and row.value.id or nil)
	end,

	pick = function(row)
		mpv:stop()
		Surface.spawn("fig-clip put " .. Text.quote(row.value.id))
		Surface.close(0)
	end,

	key = function(k)
		if k ~= "Escape" then return false end
		mpv:stop()
		Surface.close(1)
		return true
	end,
}
list.empty = "Nothing has been copied yet"

function list:onTick()
	mpv:tick(SETTLE)
end

local cfg = config.load()
Surface.font(cfg.font, cfg.size)
Surface.border("round", NOTE)
Surface.layer("overlay")
Surface.anchor("top")
Surface.margin(cfg.gap, 0, 0, 0)
-- Escape and Return are the only ways out, because both of them stop the
-- preview and losing the focus would not.
Surface.dismiss(false)
Surface.window(COLS, ROWS + 1)
Surface.every(SETTLE)
Surface.listen("theme")
Surface.run(list)
