[ -f ~/.bashrc ] && . ~/.bashrc

# The editor the image ships. yazi, git and anything else that opens a file
# asks the environment rather than being told twice.
export EDITOR=micro VISUAL=micro

# micro rounds a hex colour to the nearest of 256 without this, and the
# colourscheme the theme writes is hex.
export MICRO_TRUECOLOR=1

# What the desktop calls itself. xdg-desktop-portal picks a backend by this
# name and nothing else: xdg-desktop-portal-wlr's .portal file lists `wlroots`
# in its UseIn, so unset means the portal chooses no backend and a screencast
# request is answered by nobody.
#
# A colon list, most specific first, which is what the spec says and what
# Hyprland and sway do. The portal splits it and matches any entry, so
# `wlroots` still finds the backend; `hedl` is there because anything asking
# what is running gets the compositor's own name. Without it fastfetch and
# friends answer "wlroots", since the variable shadows the process they would
# otherwise find.
export XDG_CURRENT_DESKTOP=hedl:wlroots
export XDG_SESSION_TYPE=wayland

# tty1 is the session. Anything else is a plain shell.
#
# dbus-run-session, not a user service manager: runit has none, and every
# adapter kippsrv loads wants a session bus address in its environment.
#
# No `exec`. If hedl dies, this leaves a shell on tty1 with the log next to
# it. Replacing the shell instead would end the login, and agetty would log
# straight back in and try again once a second.
#
# hedl is not given `-s`. The shell reads it over the socket at
# $XDG_RUNTIME_DIR/hedl/kipp instead, so nothing has to be anything's child.
if [ -z "${WAYLAND_DISPLAY:-}" ] && [ "$(tty)" = /dev/tty1 ]; then
	dbus-run-session hedl >~/.hedl.log 2>&1
	echo "hedl exited. Its output is in ~/.hedl.log"
fi
