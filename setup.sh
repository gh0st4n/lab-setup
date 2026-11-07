#!/bin/bash
#
# setup.sh
# Virtualization installer for T4n OS (Void Linux based).
# Supports VirtualBox (virtualbox-ose) and virt-manager (libvirt + QEMU/KVM).
#
# Usage:
#   bash setup.sh                  # interactive menu
#   bash setup.sh --virtualbox     # install VirtualBox only
#   bash setup.sh --virt-manager   # install virt-manager only
#   bash setup.sh --all            # install both
#
# Notes:
# - Package manager is auto-detected: tpkg is used if installed,
#   otherwise the script falls back to xbps directly.
# - Do not run this with sudo; the script will prompt for a password itself when needed.
# - If the kernel was recently updated, reboot before running this script,
#   so the running kernel matches the linux-headers that will be installed
#   (relevant for VirtualBox).

set -e

usage() {
    cat <<EOF
Usage: bash $(basename "$0") [option]

Options:
  -v, --virtualbox     Install VirtualBox (virtualbox-ose + DKMS)
  -k, --virt-manager   Install virt-manager (libvirt + QEMU/KVM)
  -a, --all            Install both
  -h, --help           Show this help

Without an option, an interactive menu is shown.
EOF
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Package manager: use tpkg (T4n Package Manager) if available,
# otherwise fall back to xbps directly (plain Void Linux).
if command -v tpkg > /dev/null 2>&1; then
    PM="tpkg"
else
    PM="xbps"
fi

pkg_update() {
    if [ "${PM}" = "tpkg" ]; then
        tpkg update
    else
        sudo xbps-install -Su
    fi
}

pkg_install() {
    if [ "${PM}" = "tpkg" ]; then
        tpkg install "$@"
    else
        sudo xbps-install -S "$@"
    fi
}

enable_service() {
    svc="$1"
    if [ ! -d "/etc/sv/${svc}" ]; then
        echo "FAILED: service '${svc}' not found in /etc/sv."
        exit 1
    fi
    if [ -e "/var/service/${svc}" ]; then
        echo "    ${svc}: already enabled"
    else
        sudo ln -s "/etc/sv/${svc}" /var/service/
        echo "    ${svc}: enabled"
    fi
}

wait_service() {
    svc="$1"
    i=0
    while [ "$i" -lt 15 ]; do
        if sudo sv status "${svc}" 2>/dev/null | grep -q '^run:'; then
            return 0
        fi
        sleep 1
        i=$((i + 1))
    done
    return 1
}

# ---------------------------------------------------------------------------
# VirtualBox
# ---------------------------------------------------------------------------

install_virtualbox() {
    echo
    echo "##### VirtualBox #####"

    RUNNING_KERNEL="$(uname -r)"
    echo "==> Currently running kernel: ${RUNNING_KERNEL}"

    echo "==> Installing linux-headers"
    pkg_install linux-headers

    # Check whether headers for the currently running kernel are available.
    HEADER_DIR="/usr/lib/modules/${RUNNING_KERNEL}/build"
    if [ ! -d "${HEADER_DIR}" ]; then
        echo
        echo "WARNING: Headers for kernel ${RUNNING_KERNEL} were not found at ${HEADER_DIR}."
        echo "The kernel was likely updated recently but the system hasn't been rebooted yet."
        echo "Please reboot, then run this script again."
        exit 1
    fi

    echo "==> Installing virtualbox-ose and virtualbox-ose-dkms"
    pkg_install virtualbox-ose virtualbox-ose-dkms

    echo "==> Verifying the vboxusers group exists"
    if ! getent group vboxusers > /dev/null; then
        echo "FAILED: vboxusers group not found. Check the virtualbox-ose installation."
        exit 1
    fi

    echo "==> Adding user ${USER} to the vboxusers group"
    sudo usermod -aG vboxusers "${USER}"

    echo "==> Building VirtualBox kernel modules via DKMS"
    sudo dkms autoinstall

    echo "==> Verifying DKMS build for the running kernel"
    if ! sudo dkms status | grep -q "${RUNNING_KERNEL}.*installed"; then
        echo "FAILED: vboxdrv module for kernel ${RUNNING_KERNEL} did not build successfully."
        echo "Check details with: sudo dkms status"
        exit 1
    fi

    # vboxdrv      : main driver
    # vboxnetflt   : Bridged Adapter (net filter)
    # vboxnetadp   : Host-only adapter
    VBOX_MODULES="vboxdrv vboxnetflt vboxnetadp"

    echo "==> Loading VirtualBox kernel modules"
    for mod in ${VBOX_MODULES}; do
        MOD_ERR="$(mktemp)"
        if ! sudo modprobe "${mod}" 2>"${MOD_ERR}"; then
            echo "FAILED to load ${mod}."
            if grep -qi "key was rejected" "${MOD_ERR}"; then
                echo "This looks like a Secure Boot issue — the DKMS-built module is unsigned."
                echo "Either disable Secure Boot in the BIOS/UEFI settings, or enroll a MOK key"
                echo "to sign the DKMS module and try again."
            fi
            rm -f "${MOD_ERR}"
            exit 1
        fi
        rm -f "${MOD_ERR}"
    done

    echo "==> Verifying modules are loaded"
    for mod in ${VBOX_MODULES}; do
        if lsmod | grep -q "^${mod}"; then
            echo "OK: ${mod} loaded."
        else
            echo "FAILED: ${mod} not detected. Check 'sudo dkms status' for details."
            exit 1
        fi
    done

    echo "==> Enabling VirtualBox modules to load automatically on boot"
    printf '%s\n' ${VBOX_MODULES} | sudo tee /etc/modules-load.d/virtualbox.conf > /dev/null

    echo "==> VirtualBox setup complete."
}

# ---------------------------------------------------------------------------
# virt-manager (libvirt + QEMU/KVM)
# ---------------------------------------------------------------------------

install_virtmanager() {
    echo
    echo "##### virt-manager #####"

    echo "==> Checking CPU virtualization support"
    if grep -Eq '(vmx|svm)' /proc/cpuinfo; then
        echo "OK: CPU supports hardware virtualization."
    else
        echo "WARNING: vmx/svm flag not found. Enable VT-x/AMD-V in the BIOS/UEFI,"
        echo "otherwise VMs will run without KVM acceleration (very slow)."
    fi

    echo "==> Installing virt-manager, libvirt, and QEMU"
    pkg_install virt-manager virt-viewer libvirt qemu dnsmasq \
        bridge-utils iptables-nft edk2-ovmf swtpm

    echo "==> Verifying required groups exist"
    for grp in libvirt kvm; do
        if ! getent group "${grp}" > /dev/null; then
            echo "FAILED: group '${grp}' not found. Check the libvirt/qemu installation."
            exit 1
        fi
    done

    echo "==> Adding user ${USER} to the libvirt and kvm groups"
    sudo usermod -aG libvirt,kvm "${USER}"

    echo "==> Enabling runit services"
    enable_service dbus
    enable_service libvirtd
    enable_service virtlogd
    enable_service virtlockd

    echo "==> Waiting for libvirtd to start"
    if ! wait_service libvirtd; then
        echo "FAILED: libvirtd did not start. Check with: sudo sv status libvirtd"
        exit 1
    fi
    sleep 2

    echo "==> Configuring the default NAT network"
    if ! sudo virsh net-list --all --name | grep -qx default; then
        echo "FAILED: libvirt network 'default' not found."
        echo "Check /etc/libvirt/qemu/networks/default.xml"
        exit 1
    fi
    sudo virsh net-autostart default > /dev/null
    sudo virsh net-list --name | grep -qx default || sudo virsh net-start default > /dev/null

    echo "==> Verifying the default network is active"
    if sudo virsh net-list --name | grep -qx default; then
        echo "OK: network 'default' is active."
    else
        echo "FAILED: network 'default' is not active. Check: sudo virsh net-list --all"
        exit 1
    fi

    echo "==> Checking /dev/kvm"
    if [ -e /dev/kvm ]; then
        echo "OK: /dev/kvm is available."
    else
        echo "WARNING: /dev/kvm not found. Check BIOS virtualization settings"
        echo "or try: sudo modprobe kvm_intel   (or kvm_amd)"
    fi

    echo "==> virt-manager setup complete."
}

# ---------------------------------------------------------------------------
# Selection
# ---------------------------------------------------------------------------

DO_VBOX=0
DO_VIRTM=0

case "${1:-}" in
    -v|--virtualbox)   DO_VBOX=1 ;;
    -k|--virt-manager) DO_VIRTM=1 ;;
    -a|--all)          DO_VBOX=1; DO_VIRTM=1 ;;
    -h|--help)         usage; exit 0 ;;
    "")
        echo "Select what to install:"
        echo "  1) VirtualBox"
        echo "  2) virt-manager (libvirt + QEMU/KVM)"
        echo "  3) Both"
        echo "  q) Quit"
        printf "Choice [1/2/3/q]: "
        read -r CHOICE
        case "${CHOICE}" in
            1) DO_VBOX=1 ;;
            2) DO_VIRTM=1 ;;
            3) DO_VBOX=1; DO_VIRTM=1 ;;
            *) echo "Aborted."; exit 0 ;;
        esac
        ;;
    *)
        echo "Unknown option: $1"
        usage
        exit 1
        ;;
esac

if [ "${DO_VBOX}" -eq 1 ] && [ "${DO_VIRTM}" -eq 1 ]; then
    echo
    echo "NOTE: VirtualBox and KVM (virt-manager) compete for hardware virtualization."
    echo "Avoid running VMs from both at the same time."
fi

echo "==> Package manager: ${PM}"
echo "==> Updating repository and system"
pkg_update

[ "${DO_VBOX}" -eq 1 ] && install_virtualbox
[ "${DO_VIRTM}" -eq 1 ] && install_virtmanager

echo
echo "==> All done."
echo "Log out/in again (or reboot) for group membership to take effect"
if [ "${DO_VBOX}" -eq 1 ]; then
    echo "  - VirtualBox: open it from the application menu."
    echo "    Tip: set Graphics Controller to VBoxSVGA for Linux guests, and use NAT"
    echo "    (or Host-only + NAT) if Bridged Adapter on WiFi gives no network."
fi
if [ "${DO_VIRTM}" -eq 1 ]; then
    echo "  - virt-manager: run 'virt-manager' and connect to qemu:///system."
fi