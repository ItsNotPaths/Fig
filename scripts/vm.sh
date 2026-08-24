#!/bin/sh
# Boot the tildesh ISO in QEMU.
#
#   vm.sh                 the ISO, no radios
#   vm.sh --bt            plus the MT7925 bluetooth half over USB
#   vm.sh --wifi          plus the MT7925 wifi card over VFIO. Takes the card
#                         away from the host until the VM stops, so it refuses
#                         to run while the host's default route goes over it.
#   vm.sh --disk          add a persistent 32G disk, for an installed system
#   vm.sh --serial        no window. A login on this terminal instead
#   vm.sh --iso <path>    a specific image instead of the newest in dist/
#
# hedl wants a GPU, so the window uses virtio-vga-gl. On Arch that device is
# its own package: qemu-hw-display-virtio-vga-gl.
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

WIFI_PCI=0000:04:00.0
WIFI_IDS="14c3 7925"
BT_USB="vendorid=0x0e8d,productid=0x7925"

OVMF_CODE=/usr/share/edk2/x64/OVMF_CODE.4m.fd
OVMF_VARS=/usr/share/edk2/x64/OVMF_VARS.4m.fd

iso=""
want_bt=0
want_wifi=0
want_disk=0
want_serial=0

while [ $# -gt 0 ]; do
	case "$1" in
	--bt)   want_bt=1 ;;
	--wifi) want_wifi=1 ;;
	--disk) want_disk=1 ;;
	--serial) want_serial=1 ;;
	--iso)  shift; iso="$1" ;;
	*)      echo "unknown option: $1" >&2; exit 2 ;;
	esac
	shift
done

die() { echo "vm.sh: $*" >&2; exit 1; }

[ -n "$iso" ] || iso=$(ls -t "$root"/dist/*/*.iso "$root"/dist/*.iso 2>/dev/null | head -1) || true
[ -n "$iso" ] || die "no ISO in dist/. Run scripts/build-iso.sh first."
[ -f "$iso" ] || die "no such image: $iso"

[ -r /dev/kvm ] || die "/dev/kvm not readable"

vars="$root/dist/OVMF_VARS.fd"
[ -f "$vars" ] || cp "$OVMF_VARS" "$vars"

disk="$root/dist/tildesh.qcow2"
if [ "$want_disk" = 1 ] && [ ! -f "$disk" ]; then
	qemu-img create -f qcow2 "$disk" 32G >/dev/null
fi

set -- \
	-machine q35,accel=kvm \
	-cpu host -smp 4 -m 4G \
	-drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
	-drive if=pflash,format=raw,file="$vars" \
	-device intel-hda -device hda-duplex \
	-cdrom "$iso" \
	-boot menu=on

if [ "$want_serial" = 1 ]; then
	# The image runs agetty on ttyS0, so this terminal is the login.
	set -- "$@" -device VGA -display none -serial mon:stdio
elif qemu-system-x86_64 -device help 2>/dev/null | grep -q '"virtio-vga-gl"'; then
	set -- "$@" -device virtio-vga-gl -display gtk,gl=on
else
	# Plain VGA gives the guest a bochs-drm card, which is enough for sway on
	# llvmpipe. Slower, and it works with no extra package.
	echo "==> virtio-vga-gl missing, falling back to VGA."
	echo "==> For the fast path: pacman -S qemu-hw-display-virtio-vga-gl"
	set -- "$@" -device VGA -display gtk
fi

[ "$want_disk" = 1 ] && set -- "$@" -drive file="$disk",if=virtio,format=qcow2

# ------------------------------------------------------------------ bluetooth
#
# The BT half of the combo card is a plain USB device, so it detaches and comes
# back on its own. The host loses bluetooth while the VM holds it.
if [ "$want_bt" = 1 ]; then
	lsusb -d 0e8d:7925 >/dev/null 2>&1 || die "MT7925 bluetooth not on USB"
	set -- "$@" -device qemu-xhci -device usb-host,"$BT_USB"
fi

# ----------------------------------------------------------------------- wifi
#
# VFIO takes the whole PCI function. It is alone in its IOMMU group, so nothing
# else goes with it, but the host has no other wireless.
if [ "$want_wifi" = 1 ]; then
	route_dev=$(ip -o route show default | awk '{print $5; exit}')
	case "$route_dev" in
	wlp*|wlan*) die "the host's default route is over $route_dev. Plug in ethernet first." ;;
	"")         die "the host has no default route" ;;
	esac

	group=$(basename "$(readlink -f /sys/bus/pci/devices/$WIFI_PCI/iommu_group)")
	[ -n "$group" ] || die "no IOMMU group for $WIFI_PCI"

	echo "==> binding $WIFI_PCI to vfio-pci (IOMMU group $group)"
	sudo modprobe vfio-pci
	if [ -e "/sys/bus/pci/devices/$WIFI_PCI/driver" ]; then
		current=$(basename "$(readlink -f /sys/bus/pci/devices/$WIFI_PCI/driver)")
		[ "$current" = vfio-pci ] || \
			echo "$WIFI_PCI" | sudo tee "/sys/bus/pci/devices/$WIFI_PCI/driver/unbind" >/dev/null
	fi
	echo "$WIFI_IDS" | sudo tee /sys/bus/pci/drivers/vfio-pci/new_id >/dev/null 2>&1 || true
	sudo chown "$(id -u)" "/dev/vfio/$group"

	set -- "$@" -device vfio-pci,host="$WIFI_PCI"

	# Give it back on the way out, however qemu exits.
	restore_wifi() {
		echo "==> returning $WIFI_PCI to mt7925e"
		echo "$WIFI_PCI" | sudo tee /sys/bus/pci/drivers/vfio-pci/unbind >/dev/null 2>&1 || true
		echo "$WIFI_IDS" | sudo tee /sys/bus/pci/drivers/vfio-pci/remove_id >/dev/null 2>&1 || true
		echo "$WIFI_PCI" | sudo tee /sys/bus/pci/drivers_probe >/dev/null 2>&1 || true
	}
	trap restore_wifi EXIT INT TERM
else
	set -- "$@" -nic user,model=virtio-net-pci
fi

echo "==> $iso"
exec qemu-system-x86_64 "$@"
