#!/bin/bash
#
# setup-virtualbox-t4nos.sh
# Script instalasi VirtualBox (virtualbox-ose) untuk T4n OS (basis Void Linux).
#
# Penggunaan:
#   bash setup-virtualbox-t4nos.sh
#
# Catatan:
# - Jangan jalankan dengan sudo, script akan minta password sendiri saat perlu.
# - Jika kernel baru saja terupdate, reboot dulu sebelum menjalankan script ini,
#   supaya kernel yang berjalan sinkron dengan linux-headers yang akan dipasang.

set -e

echo "==> Update repository dan sistem"
sudo xbps-install -Su

RUNNING_KERNEL="$(uname -r)"
echo "==> Kernel yang sedang berjalan: ${RUNNING_KERNEL}"

echo "==> Memasang linux-headers"
sudo xbps-install -S linux-headers

# Cek apakah header untuk kernel yang sedang berjalan tersedia.
HEADER_DIR="/usr/lib/modules/${RUNNING_KERNEL}/build"
if [ ! -d "${HEADER_DIR}" ]; then
    echo
    echo "PERINGATAN: Header untuk kernel ${RUNNING_KERNEL} tidak ditemukan di ${HEADER_DIR}."
    echo "Kemungkinan kernel baru saja terupdate tapi sistem belum di-reboot."
    echo "Silakan reboot, lalu jalankan ulang script ini."
    exit 1
fi

echo "==> Memasang virtualbox-ose dan virtualbox-ose-dkms"
sudo xbps-install -S virtualbox-ose virtualbox-ose-dkms

echo "==> Menambahkan user ${USER} ke grup vboxusers"
sudo usermod -aG vboxusers "${USER}"

echo "==> Build dan load module kernel VirtualBox"
sudo dkms autoinstall
sudo modprobe vboxdrv

echo "==> Verifikasi module"
if lsmod | grep -q vboxdrv; then
    echo "OK: module vboxdrv berhasil dimuat."
else
    echo "GAGAL: module vboxdrv tidak terdeteksi. Cek 'sudo dkms status' untuk detail."
    exit 1
fi

echo
echo "==> Setup selesai."
echo "Logout/login ulang (atau reboot) agar keanggotaan grup vboxusers aktif,"
echo "lalu buka VirtualBox dari menu aplikasi."
