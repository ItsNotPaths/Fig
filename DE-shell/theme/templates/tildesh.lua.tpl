-- The palette, for anything of ours that draws. Written when a theme is
-- applied. Read it through lib/theme.lua, never by hand.
return {
	mode = "{{ theme_type }}",

	background        = "{{ background }}",
	dark_background   = "{{ dark_background }}",
	darker_background = "{{ darker_background }}",
	lighter_background = "{{ lighter_background }}",

	foreground        = "{{ foreground }}",
	dark_foreground   = "{{ dark_foreground }}",
	light_foreground  = "{{ light_foreground }}",
	bright_foreground = "{{ bright_foreground }}",

	accent    = "{{ accent }}",
	selection = "{{ selection }}",
	muted     = "{{ muted }}",
	cursor    = "{{ cursor }}",

	red     = "{{ red }}",
	orange  = "{{ orange }}",
	yellow  = "{{ yellow }}",
	green   = "{{ green }}",
	cyan    = "{{ cyan }}",
	blue    = "{{ blue }}",
	magenta = "{{ magenta }}",
	brown   = "{{ brown }}",

	bright_red     = "{{ bright_red }}",
	bright_yellow  = "{{ bright_yellow }}",
	bright_green   = "{{ bright_green }}",
	bright_cyan    = "{{ bright_cyan }}",
	bright_blue    = "{{ bright_blue }}",
	bright_magenta = "{{ bright_magenta }}",
}
