# lab-setup

Setup Lab untuk Ethical Hacking/Cyber Security di T4n OS atau Void Linux.

Repositori ini menyediakan script untuk menyiapkan lapisan virtualisasi pada
lab keamanan: mesin virtual terisolasi untuk berlatih penetration testing,
bug hunting, serta analisis malware/traffic tanpa menyentuh sistem host.

## Fitur

- Menginstall **VirtualBox** (`virtualbox-ose` + DKMS), lengkap dengan
  pengecekan kernel header, verifikasi build DKMS, deteksi Secure Boot, dan
  autoload modul secara permanen.
- Menginstall **virt-manager** (libvirt + QEMU/KVM), lengkap dengan setup
  service runit, keanggotaan grup, jaringan NAT default, dan pengecekan
  `/dev/kvm`.
- Aman dijalankan ulang: service yang sudah aktif dan jaringan yang sudah
  berjalan akan dilewati.
- Menu interaktif atau opsi lewat command line.

## Kebutuhan

- T4n OS atau Void Linux (glibc atau musl), memakai `xbps` dan `runit`
- CPU dengan virtualisasi hardware (VT-x / AMD-V) yang aktif di BIOS/UEFI
- User biasa dengan akses `sudo` (**jangan** jalankan script dengan `sudo`;
  script akan meminta password sendiri saat dibutuhkan)

## Cara Pakai

```sh
git clone https://github.com/T4n-Labs/lab-setup.git
cd lab-setup
bash setup.sh
```

Opsi:

| Opsi                  | Keterangan                                   |
|-----------------------|----------------------------------------------|
| *(tanpa opsi)*        | Menu interaktif                              |
| `-v`, `--virtualbox`  | Install VirtualBox saja                      |
| `-k`, `--virt-manager`| Install virt-manager (libvirt + QEMU/KVM)    |
| `-a`, `--all`         | Install keduanya                             |
| `-h`, `--help`        | Tampilkan bantuan                            |

Setelah script selesai, **logout lalu login kembali** (atau reboot) agar
keanggotaan grup baru (`vboxusers`, `libvirt`, `kvm`) berlaku.

## Yang Diinstall

**VirtualBox**

- `linux-headers`, `virtualbox-ose`, `virtualbox-ose-dkms`
- User ditambahkan ke grup `vboxusers`
- `vboxdrv`, `vboxnetflt` (Bridged Adapter), dan `vboxnetadp` (Host-only)
  dimuat sekarang dan setiap boot (`/etc/modules-load.d/virtualbox.conf`)

**virt-manager**

- `virt-manager`, `virt-viewer`, `libvirt`, `qemu`, `dnsmasq`, `bridge-utils`,
  `iptables-nft`, `edk2-ovmf` (UEFI), `swtpm` (emulasi TPM)
- User ditambahkan ke grup `libvirt` dan `kvm`
- Service runit diaktifkan: `dbus`, `libvirtd`, `virtlogd`, `virtlockd`
- Jaringan NAT `default` milik libvirt diatur autostart (`192.168.122.0/24`)

## Catatan

- **Jangan jalankan VM VirtualBox dan KVM secara bersamaan.** Keduanya
  berebut virtualisasi hardware. Menginstall keduanya tidak masalah, cukup
  pakai satu per satu.
- **Secure Boot:** modul VirtualBox hasil build DKMS tidak ditandatangani.
  Jika `vboxdrv` gagal dimuat dengan pesan "key was rejected", matikan Secure
  Boot atau enroll kunci MOK untuk menandatangani modul.
- **Update kernel:** jika kernel baru saja diperbarui, reboot dulu sebelum
  menginstall VirtualBox agar kernel yang berjalan cocok dengan header yang
  terpasang.
- `virbr0` akan berstatus `NO-CARRIER` / `DOWN` selama belum ada VM yang
  terhubung ke jaringan `default`. Ini normal.

## Menjalankan T4n OS sebagai Guest di VirtualBox

- **Graphics Controller:** gunakan **VBoxSVGA** (Settings → Display).
  Dengan **VMSVGA**, kernel guest memuat driver `vmwgfx` yang menolak jalan
  di VirtualBox dan menampilkan error `vmwgfx seems to be running on an
  unsupported hypervisor`. Boot tetap lanjut, tetapi grafis bisa kurang
  optimal.
- **Guest Additions:** di dalam guest install `virtualbox-ose-guest` dan
  `virtualbox-ose-guest-dkms`, lalu aktifkan service `vboxservice`
  (`sudo ln -s /etc/sv/vboxservice /var/service/`). Ini memberi resolusi
  otomatis, clipboard bersama, dan mouse integration.
- **Jaringan:** Bridged Adapter pada WiFi sering tidak stabil karena banyak
  access point menolak beberapa MAC address dari satu klien. Jika VM tidak
  mendapat IP, pakai **NAT**, atau **Host-only + NAT** (dua adapter) yang
  lebih stabil dan lebih terisolasi untuk lab.

## Troubleshooting

| Masalah | Cek |
|---------|-----|
| virt-manager tidak bisa terhubung ke `qemu:///system` | `sudo sv status libvirtd`, dan pastikan user ada di grup `libvirt` (login ulang) |
| VM tidak ada internet | `cat /proc/sys/net/ipv4/ip_forward` harus `1`; cek aturan firewall untuk NAT |
| `/dev/kvm` tidak ada | Aktifkan VT-x/AMD-V di BIOS/UEFI, atau `sudo modprobe kvm_intel` / `kvm_amd` |
| VM gagal start dengan `VERR_SUPDRV_COMPONENT_NOT_FOUND` (Bridged/Host-only) | `lsmod \| grep vbox` harus menampilkan `vboxdrv`, `vboxnetflt`, `vboxnetadp`; jika belum: `sudo modprobe vboxnetflt vboxnetadp` |
| `vboxdrv` gagal di-build | `sudo dkms status`; pastikan header sesuai dengan `uname -r` |

## Disclaimer

Lab ini ditujukan untuk riset dan edukasi keamanan yang **legal dan etis**.
Hanya uji sistem milik sendiri atau yang sudah mendapat izin tertulis secara
eksplisit. Penggunaan sepenuhnya menjadi tanggung jawab kamu.

---

<div align="center">

[@T4n-Labs](https://t4nlabs.web.id) · [@Gh0sT4n](https://gh0st4n.my.id)

</div>