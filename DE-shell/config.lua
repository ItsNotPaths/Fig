-- The shell, as opposed to the window manager or the renderer.
--
-- wweft draws and hedl arranges windows. Neither has an opinion about how big
-- the text is, so it is here, and every surface reads it through
-- lib/settings.lua rather than choosing for itself.
--
-- Edit and press SUPER+SHIFT+R.
return {
	-- Two names for one typeface, because they are asked for differently:
	-- wweft opens a file, foot asks fontconfig. "" lets wweft pick.
	font   = "",
	family = "IosevkaTerm Nerd Font Mono",
	-- Pixels tall, for the surfaces and for foot alike. foot would read a
	-- bare number as points, so the file written for it says px.
	size   = 16,

	-- 12 or 24. The date beside it does not change either way.
	clock = 12,

	-- Where the weather is: a place name, a "lat,lon" pair, or "" to work it
	-- out from the address the internet sees. A name is looked up once and
	-- the answer kept, so this costs one request either way.
	place = "",

	-- "" takes the temperature from where you are: Fahrenheit in the countries
	-- that use it, Celsius everywhere else. "C" or "F" forces it. The wind
	-- follows either way, km/h or mph.
	degrees = "",

	-- The bar sits this many pixels below the top edge, to line up with
	-- hedl's `gaps`. 0 puts it back against the edge.
	gap = 8,

	-- Applied once, on a home that has never had a theme picked. After that
	-- the picker decides and this is ignored.
	theme = "gruvbox",

	-- foot cannot read a Lua table, so the size is written to a file it
	-- includes. Set false to leave foot alone and size it in foot.ini.
	size_foot = true,
}
