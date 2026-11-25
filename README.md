# zflip3-fedora-kde

Fedora 45 KDE Plasma Desktop (aarch64, dari image RAW resmi) untuk Samsung Galaxy Z Flip3 5G (`b2q`, SM-F711N).
Boot chain memakai port `noas-slopware/linux-zflip3`: ABL → U-Boot (`boot`) → kernel
dari `recovery`, DTBO dikosongkan. OpenWrt lama akan ditimpa (disetujui).

## Status

- [x] Kernel **full-driver** (config `nura-sm8350.config` + `b2q.fragment`, patch
      `patches/linux/[0-9][0-9][0-9][0-9]-*.patch`) dibangun di GitHub Actions
      public runner `ubuntu-24.04-arm` — workflow `.github/workflows/build-kernel.yml`.
- [ ] Rootfs Fedora 45 KDE Plasma Desktop (image RAW resmi → tar) — `scripts/build-rootfs.sh`.
- [ ] Suntik modul + firmware + konfigurasi perangkat ke rootfs.
- [ ] Uji boot tethered, lalu install via installer port (stream tar ke `nc 5555`).

Kenapa kernel port, bukan kernel Fedora stok: patch b2q (panel 120 Hz, UFS,
charging, sensor, kamera, modem) tidak ada di kernel Fedora. Kernel dibangun
dengan krelease `7.3.5-2-zflip3` supaya kompatibel dengan paket modul port.

## Pakai

```sh
gh workflow run build-kernel.yml
gh run watch
gh run download <run-id> -R mift2609/zflip3-fedora-kde
```

Artefak: `Image.gz`, `sm8350-samsung-b2q.dtb`, `modules.tar.zst`,
`kernel.config`, `kernelrelease`, `SHA256SUMS`.

Rootfs Fedora belum ada di repo ini; ini project baru, bukan fork OpenWrt.
