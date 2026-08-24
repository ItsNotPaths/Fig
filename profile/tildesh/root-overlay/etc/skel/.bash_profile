[ -f ~/.bashrc ] && . ~/.bashrc

# The editor the image ships. yazi, git and anything else that opens a file
# asks the environment rather than being told twice.
export EDITOR=micro VISUAL=micro

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
