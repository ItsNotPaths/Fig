-- What a weather code means, in a glyph and in words.
--
-- Open-Meteo answers in WMO codes. The glyphs are omarchy's own, off its
-- weather panel, so the desktop reads the same; it groups drizzle with rain
-- and showers with rain, and so does this.

local M = {}

local CLEAR   = {"\u{e30d}", "\u{e32b}"}     -- day, night
local CLOUDY  = {"\u{e302}", "\u{e32e}"}
local OVERCAST = {"\u{e33d}", "\u{e33d}"}
local FOG     = {"\u{e313}", "\u{e346}"}
local RAIN    = {"\u{e318}", "\u{e318}"}
local SNOW    = {"\u{e31a}", "\u{e31a}"}
local STORM   = {"\u{e31d}", "\u{e31d}"}

local GLYPH = {
	[0] = CLEAR,
	[1] = CLOUDY, [2] = CLOUDY, [3] = OVERCAST,
	[45] = FOG, [48] = FOG,
	[51] = RAIN, [53] = RAIN, [55] = RAIN, [56] = RAIN, [57] = RAIN,
	[61] = RAIN, [63] = RAIN, [65] = RAIN, [66] = RAIN, [67] = RAIN,
	[71] = SNOW, [73] = SNOW, [75] = SNOW, [77] = SNOW,
	[80] = RAIN, [81] = RAIN, [82] = RAIN,
	[85] = SNOW, [86] = SNOW,
	[95] = STORM, [96] = STORM, [99] = STORM,
}

local WORDS = {
	[0] = "clear",
	[1] = "mainly clear", [2] = "partly cloudy", [3] = "overcast",
	[45] = "fog", [48] = "freezing fog",
	[51] = "light drizzle", [53] = "drizzle", [55] = "heavy drizzle",
	[56] = "freezing drizzle", [57] = "freezing drizzle",
	[61] = "light rain", [63] = "rain", [65] = "heavy rain",
	[66] = "freezing rain", [67] = "freezing rain",
	[71] = "light snow", [73] = "snow", [75] = "heavy snow",
	[77] = "snow grains",
	[80] = "showers", [81] = "showers", [82] = "heavy showers",
	[85] = "snow showers", [86] = "snow showers",
	[95] = "thunderstorm", [96] = "thunderstorm and hail",
	[99] = "thunderstorm and hail",
}

function M.glyph(code, night)
	local pair = GLYPH[tonumber(code) or -1] or OVERCAST
	return pair[night and 2 or 1]
end

function M.words(code)
	return WORDS[tonumber(code) or -1] or "unknown"
end

return M
