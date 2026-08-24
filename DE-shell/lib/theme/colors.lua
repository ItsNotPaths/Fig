-- colors.toml, resolved.
--
-- A theme file names some colours and leaves the rest implied. A template may
-- use any of them, so the implied ones have to exist before anything renders.
-- This is a port of omarchy-theme-color, and the order below is its order:
-- get it wrong and a theme written for omarchy renders different colours here.
--
-- Verified against `omarchy-theme-color --all` over every shipped theme.

local M = {}

local function hex_byte(s, i)
	return tonumber(s:sub(i, i + 1), 16) or 0
end

-- Amount is a fraction, a percentage, or a whole number meaning percent.
function M.mix(from, to, amount)
	local a = tonumber((tostring(amount):gsub("%%$", ""))) or 0
	if tostring(amount):find("%%$") or a > 1 then a = a / 100 end
	a = math.max(0, math.min(1, a))

	local s, e = from:gsub("^#", ""), to:gsub("^#", "")
	local out = "#"
	for i = 1, 5, 2 do
		local v = hex_byte(s, i) * (1 - a) + hex_byte(e, i) * a
		out = out .. string.format("%02x", math.floor(v + 0.5))
	end
	return out
end

function M.rgb(hex)
	local h = hex:gsub("^#", "")
	return ("%d,%d,%d"):format(hex_byte(h, 1), hex_byte(h, 3), hex_byte(h, 5))
end

-- Values reach a template as replacement text and a key reaches it as a
-- pattern, so both are held to a charset. A theme from a stranger is data we
-- did not write.
local KEY_OK   = "^[%w_%-]+$"
local VALUE_OK = "^[%w#(),._+/%% %-]*$"

local function parse(path)
	local t, f = {}, io.open(path)
	if not f then return nil end

	for line in f:lines() do
		local key, value = line:match("^%s*([^=]-)%s*=%s*(.-)%s*$")
		if key then
			key = key:gsub("[\"' ]", "")
			local quoted = value:match("^[\"'](.-)[\"']")
			value = quoted or value

			if key ~= "" and not key:find("^#") then
				if not key:match(KEY_OK) then
					io.stderr:write("palette: skipping a key with unusable characters\n")
				elseif not value:match(VALUE_OK) then
					io.stderr:write("palette: skipping " .. key .. ": unusable characters\n")
				else
					t[key] = value
				end
			end
		end
	end
	f:close()
	return t
end

-- Only when it has none of its own.
local function alias(t, key, from)
	if not t[key] or t[key] == "" then t[key] = t[from] end
end

local LEGACY_SHORT = {
	background = "bg", dark_background = "dark_bg",
	darker_background = "darker_bg", lighter_background = "lighter_bg",
	foreground = "fg", dark_foreground = "dark_fg",
	light_foreground = "light_fg", bright_foreground = "bright_fg",
}

local FROM_ANSI = {
	red = "color1", green = "color2", yellow = "color3", blue = "color4",
	magenta = "color5", cyan = "color6", bright_red = "color9",
	bright_green = "color10", bright_yellow = "color11",
	bright_blue = "color12", bright_magenta = "color13",
	bright_cyan = "color14",
}

local TO_ANSI = {
	color0 = "background", color1 = "red", color2 = "green", color3 = "yellow",
	color4 = "blue", color5 = "magenta", color6 = "cyan", color7 = "foreground",
	color8 = "muted", color9 = "bright_red", color10 = "bright_green",
	color11 = "bright_yellow", color12 = "bright_blue",
	color13 = "bright_magenta", color14 = "bright_cyan",
	color15 = "bright_foreground",
}

local function first(t, ...)
	for _, key in ipairs({...}) do
		if t[key] and t[key] ~= "" then return t[key] end
	end
end

-- Dark unless the file says otherwise, a light.mode file sits beside it, or
-- the background is bright enough to be one.
local function resolve_mode(t, dir)
	alias(t, "mode", "theme_type")
	if t.mode and t.mode ~= "" then return end

	local marker = io.open(dir .. "/light.mode")
	if marker then
		marker:close()
		t.mode = "light"
		return
	end

	local bg = t.background and t.background:match("^#(%x%x%x%x%x%x)$")
	if bg and hex_byte(bg, 1) + hex_byte(bg, 3) + hex_byte(bg, 5) > 382 then
		t.mode = "light"
	else
		t.mode = "dark"
	end
end

function M.load(path)
	local t = parse(path)
	if not t then return nil end

	for key, short in pairs(LEGACY_SHORT) do alias(t, key, short) end

	-- A theme that names only ANSI colours still has a background.
	alias(t, "background", "color0")
	alias(t, "foreground", "color7")
	if t.background then t.color0 = t.background end
	if t.foreground then t.color7 = t.foreground end

	for key, from in pairs(FROM_ANSI) do alias(t, key, from) end
	alias(t, "magenta", "purple")
	alias(t, "bright_magenta", "bright_purple")

	t.light_foreground  = t.light_foreground  or first(t, "color7", "foreground")
	t.bright_foreground = t.bright_foreground or first(t, "color15", "foreground")
	t.cursor            = t.bright_foreground
	t.lighter_background = t.lighter_background or first(t, "color0", "background")
	t.dark_foreground   = t.dark_foreground   or first(t, "color8", "foreground")
	t.muted             = t.muted             or first(t, "color8", "dark_foreground")
	t.selection         = t.selection or
		first(t, "selection_background", "color8", "color0", "background")
	t.selection_background = t.selection_background or t.selection
	t.selection_foreground = t.selection_foreground or t.bright_foreground
	t.orange            = t.orange            or t.yellow
	t.brown             = t.brown             or M.mix(t.orange, "#000000", "50%")

	t.dark_background   = t.dark_background   or M.mix(t.background, "#000000", "25%")
	t.darker_background = t.darker_background or M.mix(t.background, "#000000", "50%")
	for _, name in ipairs({"red", "yellow", "green", "cyan", "blue", "magenta"}) do
		local bright = "bright_" .. name
		t[bright] = t[bright] or M.mix(t[name], "#ffffff", "20%")
	end
	alias(t, "purple", "magenta")
	alias(t, "bright_purple", "bright_magenta")

	for key, from in pairs(TO_ANSI) do alias(t, key, from) end
	for key, short in pairs(LEGACY_SHORT) do
		if t[key] and t[key] ~= "" then t[short] = t[key] end
	end

	resolve_mode(t, path:match("^(.*)/[^/]*$") or ".")
	t.theme_type = t.mode
	return t
end

return M
