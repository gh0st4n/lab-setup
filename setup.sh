#!/bin/bash
#
# setup-virtualbox-t4nos.sh
# VirtualBox (virtualbox-ose) installer script for T4n OS (Void Linux based).
#
# Usage:
#   bash setup-virtualbox-t4nos.sh
#
# Notes:
# - Do not run this with sudo; the script will prompt for a password itself when needed.
# - If the kernel was recently updated, reboot before running this script,
#   so the running kernel matches the linux-headers that will be installed.

set -e

echo "==> Updating repository and system"
sudo xbps-install -Su

RUNNING_KERNEL="$(uname -r)"
echo "==> Currently running kernel: ${RUNNING_KERNEL}"

echo "==> Installing linux-headers"
sudo xbps-install -S linux-headers

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
sudo xbps-install -S virtualbox-ose virtualbox-ose-dkms

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

echo "==> Loading the vboxdrv kernel module"
VBOXDRV_ERR="$(mktemp)"
if ! sudo modprobe vboxdrv 2>"${VBOXDRV_ERR}"; then
    echo "FAILED to load vboxdrv."
    if grep -qi "key was rejected" "${VBOXDRV_ERR}"; then
        echo "This looks like a Secure Boot issue — the DKMS-built module is unsigned."
        echo "Either disable Secure Boot in the BIOS/UEFI settings, or enroll a MOK key"
        echo "to sign the DKMS module and try again."
    fi
    rm -f "${VBOXDRV_ERR}"
    exit 1
fi
rm -f "${VBOXDRV_ERR}"

echo "==> Verifying module is loaded"
if lsmod | grep -q vboxdrv; then
    echo "OK: vboxdrv module loaded successfully."
else
    echo "FAILED: vboxdrv module not detected. Check 'sudo dkms status' for details."
    exit 1
fi

echo "==> Enabling vboxdrv to load automatically on boot"
echo "vboxdrv" | sudo tee /etc/modules-load.d/virtualbox.conf > /dev/null

echo
echo "==> Setup complete."
echo "Log out/in again (or reboot) for vboxusers group membership to take effect,"
echo "then open VirtualBox from the application menu."
