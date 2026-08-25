-- The keyboard, as hedl tells it.
--
-- hedl publishes one fact for each key its config bound, when the config
-- loads and when a reader connects:
--
--   bind	SUPER + SHIFT + R	desc=Reload
--
-- so this file reads a fact store and nothing else. Another window manager
-- goes in another file beside this one: `hyprctl binds -j` for Hyprland,
-- config text for sway, whatever river can be made to say. They all hand back
-- the same rows, and the surface that draws them never learns which is which.

return {
	rows = function(facts)
		local out = {}
		for f in facts:each("bind") do
			out[#out + 1] = {key = f.subj[1], desc = f.attr.desc or ""}
		end
		return out
	end,
}
