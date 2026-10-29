# SI-GIBAS

Proyek kuliah Mobile Programming menggunakan Flutter. Versi aktif memakai satu perangkat Android dan database lokal bersama untuk Kader, Badan Gizi, serta Pemerintah. Seluruh data latihan bersifat dummy; tidak membutuhkan backend.

## Menjalankan

Gunakan Flutter dan dependensi pada `pubspec.lock`. Pemasangan tambahan mengikuti persetujuan pemilik proyek.

```powershell
flutter analyze --no-pub
flutter test --no-pub
flutter build apk --release --no-pub
```

Database Android dibuat otomatis dalam penyimpanan privat ketika aplikasi dijalankan. Dua profil contoh ditambahkan hanya jika belum ada profil. Tetapkan tiga PIN berbeda saat persiapan akun, lalu gunakan ID `kader`, `gizi`, atau `pemerintah`. Tidak ada PIN bawaan. Jangan menghapus data aplikasi untuk mengatasi lupa PIN.

## Alur utama

Kader membuat profil dan pengukuran, mengajukan pemeriksaan, lalu memperbaiki pengajuan yang ditolak. Badan Gizi memberi catatan dan persetujuan. Pemerintah membaca agregat, dashboard dan ekspor PDF/Excel tanpa nama anak. Revisi, arsip/pemulihan, foto dummy, acuan gizi, kurva pertumbuhan dan jadwal kontrol berada dalam modul aplikasi yang sama.

## Dokumentasi dan pengujian

Dokumentasi teknis dan laporan berada di folder `Pertemuan 8` pada workspace kuliah. Referensi dan metode verifikasi gizi tersedia di `docs/nutrition/`. Bukti parser ekspor serta performa host tersedia di `docs/verification/`. Tes performa memakai 100 profil dummy dengan penyimpanan berkas terenkripsi pada Windows; tidak mewakili performa Android.

Kode server dan sinkronisasi lama dipertahankan sebagai riwayat pengembangan dan tidak dibutuhkan untuk versi offline. Layanan Talsec tidak diaktifkan. Konfigurasi release saat ini memakai kunci debug lokal; bukan konfigurasi penandatanganan untuk distribusi publik. Verifikasi APK dan hasil uji Android harus dibedakan dari tes browser dan host. Aplikasi ini tidak menetapkan diagnosis atau terapi individual.

Pengembangan memakai pustaka terbuka dan bantuan AI. Mahasiswa bertanggung jawab memahami dan menjelaskan kode, sumber acuan, hasil pengujian serta batas penerapannya.

## Repositori proyek final

https://github.com/mzbagus12/SIGIBAS

Kode kandidat berada pada branch `codex/tahap4-completion`. Repositori SIGIBAS-MVP tetap menjadi riwayat versi awal yang terpisah. APK, database operasional, kunci dan memory tidak disertakan dalam repositori ini.
