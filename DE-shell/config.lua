-- The shell, as opposed to the window manager or the renderer.
--
-- wweft draws and hedl arranges windows. Neither has an opinion about how big
-- the text is, so it is here, and every surface reads it through
-- lib/config.lua rather than choosing for itself.
--
-- Edit and press SUPER+SHIFT+R.
return {
	-- Two names for one typeface, because they are asked for differently:
	-- wweft opens a file, foot asks fontconfig. "" lets wweft pick.
	font   = "",
	family = "IosevkaTerm Nerd Font Mono",
	size   = 16,

	-- foot cannot read a Lua table, so the size is written to a file it
	-- includes. Set false to leave foot alone and size it in foot.ini.
	size_foot = true,
}
