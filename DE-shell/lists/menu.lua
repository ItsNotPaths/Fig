-- The menu. One row for each thing the desktop can be asked to do.
--
-- The shape is omarchy's: an id with dots in it makes the tree, so
-- "style.theme" sits under "style" and "style" sits at the root. A row with
-- an `action` does something; a row without one is a submenu. The rows are a
-- list and not a table because the order they are written in is the order
-- they are drawn in.
--
--   id       where it sits. Dots make the tree
--   icon     one glyph
--   label    what it says
--   action   a shell command. Without one, the row is a submenu
--   kipp     a command for the kippsrv socket instead of a shell
--   when     a shell condition. The row is hidden when it fails
--   checked  a shell condition. A tick is drawn when it succeeds
--
-- `when` is how a row for something optional ships without lying: the row for
-- a manual nobody installed is not there, rather than there and broken.
--
-- The contents are ours. What omarchy names, omarchy runs, and none of those
-- commands exist here; what survived the port is the shape and the wording.

local shell = "wweft ~/.config/figshell/"
local edit  = "foot -e micro "
-- The package panels are fzf, so they need a terminal. fzf and not a wweft
-- surface on purpose: `yay -Slqa` is about ninety thousand names and fzf
-- filters that incrementally with a matcher written for it. wweft has none,
-- and lib/picker.lua filters in Lua, which is right for twenty themes.
--
-- Each panel ends on omarchy-show-done, so the window stays until a key.
local term  = "foot -e "

return {
	-- Root
	{id = "apps",    icon = "󰀻", label = "Apps",    action = shell .. "apps.lua"},
	{id = "learn",   icon = "󰧑", label = "Learn"},
	{id = "trigger", icon = "󱓞", label = "Trigger"},
	{id = "style",   icon = "",  label = "Style"},
	{id = "setup",   icon = "",  label = "Setup"},
	{id = "pkg",     icon = "󰏖", label = "Packages"},
	{id = "system",  icon = "",  label = "System"},

	-- Learn
	{id = "learn.keys", icon = "", label = "Keybindings", action = shell .. "keys.lua"},
	{id = "learn.hedl", icon = "", label = "Window manager", action = "foot -e man hedl"},
	{id = "learn.kipp", icon = "󰘦", label = "What kippsrv says",
	 action = "foot -e test-wweft"},
	-- Nothing on this image opens a URL. The rows are here for a machine that
	-- has grown a browser, and absent on one that has not.
	{id = "learn.arch", icon = "󰣇", label = "Arch wiki",
	 when = "command -v xdg-open",
	 action = "xdg-open https://wiki.archlinux.org/title/Main_page"},
	{id = "learn.bash", icon = "󱆃", label = "Bash",
	 when = "command -v xdg-open",
	 action = "xdg-open https://devhints.io/bash"},

	-- Trigger
	{id = "trigger.clipboard", icon = "󰲝", label = "Clipboard history",
	 action = shell .. "clipboard.lua"},
	{id = "trigger.screenshot", icon = "", label = "Screenshot",
	 action = "bar-actions screenshot"},
	{id = "trigger.record", icon = "󰻂", label = "Record",
	 checked = "pgrep -f '^gpu-screen-recorder' >/dev/null",
	 action = "bar-actions record"},
	{id = "trigger.nightlight", icon = "󰔎", label = "Night light",
	 checked = "pgrep -x wlsunset >/dev/null",
	 action = "bar-actions nightlight"},
	{id = "trigger.stayawake", icon = "󰅶", label = "Stay awake",
	 checked = "! pgrep -x swayidle >/dev/null",
	 action = "bar-actions stayawake"},

	-- Style
	{id = "style.theme",  icon = "󰸌", label = "Theme",  action = shell .. "theme-picker.lua"},
	{id = "style.size",   icon = "", label = "Text size", action = shell .. "display.lua"},
	{id = "style.config", icon = "", label = "Shell settings",
	 action = edit .. "~/.config/figshell/config.lua"},

	-- Setup
	{id = "setup.display",   icon = "󰒓", label = "Settings",  action = shell .. "display.lua"},
	-- The only surface here that is not ours. wlay drags the outputs around
	-- and applies over wlr-output-management, which hedl already creates.
	{id = "setup.monitors",  icon = "󰹑", label = "Monitors",  action = "wlay"},
	{id = "setup.network",   icon = "󰛳", label = "Network",   action = shell .. "network.lua"},
	{id = "setup.bluetooth", icon = "󰂯", label = "Bluetooth", action = shell .. "bluetooth.lua"},
	{id = "setup.sound",     icon = "󰕾", label = "Sound",     action = shell .. "sound.lua"},
	{id = "setup.keys",      icon = "", label = "Edit keybindings",
	 action = edit .. "~/.config/hedl/hedl.lua"},

	-- Packages. omarchy's panels, under their own names, so an upstream fix
	-- to one arrives as a diff rather than a merge. Every label says what it
	-- does on its own: a row found by searching is read without the trail
	-- beside it, and the trail is there to say where it lives, not what it is.
	{id = "pkg.install", icon = "󰏗", label = "Install package",
	 action = term .. "omarchy-pkg-install"},
	{id = "pkg.aur", icon = "󰣧", label = "Install AUR package",
	 action = term .. "omarchy-pkg-aur-install"},
	{id = "pkg.remove", icon = "󰆴", label = "Uninstall package",
	 action = term .. "omarchy-pkg-remove"},
	{id = "pkg.update", icon = "󰚰", label = "Update system packages",
	 action = term .. "bash -c 'yay -Syu; omarchy-show-done $?'"},

	-- System
	{id = "system.lock",     icon = "",  label = "Lock",     action = "bar-actions lock"},
	{id = "system.suspend",  icon = "󰒲", label = "Suspend",  action = "loginctl suspend"},
	{id = "system.logout",   icon = "󰍃", label = "Log out",  kipp = "QUIT"},
	{id = "system.reboot",   icon = "󰜉", label = "Reboot",   action = "loginctl reboot"},
	{id = "system.shutdown", icon = "󰐥", label = "Shut down", action = "loginctl poweroff"},
}
