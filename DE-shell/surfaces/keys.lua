-- The keyboard. What every key does, filtered as you type.
--
--   type        filter, on what it does or on the key itself. "mod + k",
--               "MOD+K" and "super k" all find the same row
--   Up/Down     move
--   Escape      close
--
-- hedl publishes one `bind` fact for each key its config bound, so this asks
-- nobody and parses nothing. Which window manager wrote them is
-- wm-bind-parsers/'s business: one file each, all handing back the same rows.
--
-- Return does not press the key. A bind can be a Lua function inside the
-- window manager, and there is no honest way to reach that from out here. This
-- is a sheet to read, so Return closes it like Escape does.

local kipp    = require("lib.kipp")
local picker  = require("lib.picker")
local palette = require("lib.palette")
local config  = require("lib.settings")
local wm      = require("wm-bind-parsers.hedl")

local COLS, ROWS = 54, 14

-- Every name for the same modifier. A key is typed in a hurry and from
-- memory, and half these words are what the other keyboard called it.
local SAME = {
	mod = "super", cmd = "super", command = "super", win = "super",
	windows = "super", meta = "super", logo = "super", gui = "super",
	control = "ctrl",
	option = "alt", opt = "alt",
	enter = "return",
	esc = "escape",
	spc = "space",
	del = "delete",
	pgup = "prior", pgdn = "next",
}

-- "mod + k", "MOD+K" and "super k" are one thing. Both sides are folded
-- before they meet: each word becomes the one name for it, and whatever
-- separated them stops mattering.
local function words(text)
	local out = {}
	for word in text:lower():gmatch("%w+") do
		out[#out + 1] = SAME[word] or word
	end
	return out
end

-- The query folds once for the whole list rather than once for each row.
local asked, wanted = nil, {}

-- One word of the query against the words of one key. A short word has to
-- start a key's word, or "r" would find the r in "super" and every shifted
-- bind with it. Three characters is enough to mean it, so from there it may
-- sit anywhere: "audio" finds XF86AudioRaiseVolume.
local function hit(word, keys)
	for _, key in ipairs(keys) do
		if key:sub(1, #word) == word then return true end
		if #word >= 3 and key:find(word, 1, true) then return true end
	end
	return false
end

-- Every word of the query has to be in the key somewhere, in any order. So
-- "mod 1" finds everything super and 1 do together, "shift 1" finds only the
-- one that takes shift, and half a word still finds the key while it is
-- being typed.
local function match(row, query)
	if query ~= asked then
		asked, wanted = query, words(query)
	end
	if Text.contains(row.text, query) then return true end
	if #wanted == 0 then return false end

	for _, word in ipairs(wanted) do
		if not hit(word, row.keys) then return false end
	end
	return true
end

local facts = kipp.store()

local function rows()
	local out = {}
	for _, b in ipairs(wm.rows(facts)) do
		out[#out + 1] = {
			text  = b.desc ~= "" and b.desc or b.key,
			note  = b.key,
			keys  = words(b.key),
			value = b.key,
		}
	end
	return out
end

local list = picker.new{
	prompt  = "Keys",
	rows    = ROWS,
	sources = {{name = "binds", rows = rows}},
	match   = match,
	pick    = function() Surface.close(0) end,
	key     = function(k)
		if k ~= "Escape" then return false end
		Surface.close(1)
		return true
	end,
}
list.empty = "The window manager has said nothing"

function list:onMessage(line)
	if palette.changed(line) then return end
	if facts:feed(line) == "bind" then self:refresh() end
end

local cfg = config.load()
Surface.font(cfg.font, cfg.size)
Surface.border("round", list.style.title)
Surface.layer("overlay")
Surface.anchor("center")
Surface.window(COLS, ROWS + 1)
Surface.listen(kipp.socket)
Surface.listen("theme")
Surface.run(list)
