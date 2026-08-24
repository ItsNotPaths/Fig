-- What the record popup offers, and where it puts the file.
--
-- The rows at the top of the popup are these, in this order. The pickers under
-- them are always there: the sound, every monitor, and every window open right
-- now. Press c in the popup to open this file at the line below.
--
-- Edit and press SUPER+SHIFT+R.
return {
	-- Where a recording lands. gpu-screen-recorder names the file itself.
	output = "~/Videos",

	-- One row each. `audio` is "system", "mic" or "none". `monitors` is
	-- "focused" for whichever one you are looking at, "all" for every one at
	-- once, or a list of names as hedl reports them: {"eDP-1", "DP-1"}.
	configs = {
		{name = "Screen",  audio = "system", monitors = "focused"},
		{name = "Silent",  audio = "none",   monitors = "focused"},
		{name = "Talking", audio = "mic",    monitors = "focused"},
		{name = "Both",    audio = "system", monitors = "all"},
	},
}
