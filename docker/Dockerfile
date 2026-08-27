# The Artix build host. buildiso needs chroot, mount and loop devices, so the
# container runs --privileged. Nothing else here is unusual.
FROM artixlinux/artixlinux:base-devel

# makepkg runs --nodeps in here, so anything a package needs to build has to be
# in the image already. Lines two and three are hedl's, line four is wlay's:
# extra-cmake-modules only for its FindWayland and FindWaylandScanner modules,
# which is what wlay's CMakeLists asks for.
RUN pacman -Syu --noconfirm --needed \
        artools-iso git jq \
        wlroots0.20 wayland wayland-protocols libxkbcommon libinput \
        libxcb xcb-util-wm lua54 \
        cmake extra-cmake-modules pkgconf glfw libepoxy \
    && pacman -Scc --noconfirm

# artools 0.39.1: configure_calamares() ends on a directory test, so a profile
# that ships no Calamares makes the function return 1. buildiso runs under
# `set -e` with an ERR trap, so it aborts a rootfs that is already finished.
# Leaving early when there is nothing to configure is what the function means.
RUN sed -i \
        's|^configure_calamares(){|configure_calamares(){\n    [[ -d "$1"/etc/calamares-online \|\| -d "$1"/etc/calamares-offline ]] \|\| return 0|' \
        /usr/share/artools/lib/iso/calamares.sh \
    && bash -n /usr/share/artools/lib/iso/calamares.sh

# makepkg refuses to run as root, and everything else here is root.
RUN useradd -m builder

# WORKSPACE_DIR/iso-profiles overrides the packaged profiles, and the profile's
# own common/ overrides the packaged common. Both are bind mounts.
RUN printf '%s\n' \
        'CHROOTS_DIR=/var/lib/artools' \
        'WORKSPACE_DIR=/workspace' \
        'ISO_POOL=/out' \
        'INITSYS=runit' \
        'COMPRESSION=zstd' \
        'COMPRESSION_LEVEL=15' \
        > /etc/artools/artools-iso.conf

# buildiso prefers ~/.config/artools/pacman.conf.d over the packaged one, so
# our own packages get a repo. Derived from the shipped file rather than
# copied into the tree, so an Artix mirror change is not ours to track.
# file:///repo is a bind mount, and it is signed by nobody.
RUN mkdir -p /root/.config/artools/pacman.conf.d \
    && sed '/^\[system\]/i [fig]\nSigLevel = Optional TrustAll\nServer = file:///repo\n' \
        /usr/share/artools/pacman.conf.d/iso-x86_64.conf \
        > /root/.config/artools/pacman.conf.d/iso-x86_64.conf \
    && grep -q '^\[fig\]' /root/.config/artools/pacman.conf.d/iso-x86_64.conf

WORKDIR /workspace
