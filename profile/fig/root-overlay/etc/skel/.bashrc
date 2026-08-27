# Interactive shells. foot starts one of these, and .bash_profile sources this
# file so a login shell gets the same thing.

# mise puts the runtime a directory asks for at the front of PATH. Without
# this line it is installed and does nothing.
command -v mise >/dev/null && eval "$(mise activate bash)"
