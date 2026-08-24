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

	-- Applied once, on a home that has never had a theme picked. After that
	-- the picker decides and this is ignored.
	theme = "gruvbox",

	-- foot cannot read a Lua table, so the size is written to a file it
	-- includes. Set false to leave foot alone and size it in foot.ini.
	size_foot = true,
}
