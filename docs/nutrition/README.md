# AKG, PMT dan kurva pertumbuhan lokal

Modul ini hanya untuk simulasi data sintetis, berjalan offline tanpa layanan eksternal. Tidak ada validasi klinis atau uji pengguna manusia yang diklaim.

## Integrasi

```dart
import 'nutrition_panel.dart';
NutritionGrowthPanel(
  key: ValueKey('nutrition-$childId'),
  child: Map<String, dynamic>.from(child),
  history: repo.growthHistory(childId),
  today: repo.today,
)
```

Letakkan dalam induk yang dapat digulir. `child` memakai `id`, `birth` ISO civil date, `sex` (`male`/`female`) dan `name`. `history` memakai skema revisi repository, persetujuan efektif per pengukuran; panel juga menyaring status approved. `today` adalah tanggal acuan aplikasi. Kunci per anak mencegah input skrining sintetis terbawa ke anak lain. Input recall, alergi dan tanda bahaya bersifat sementara, tidak disimpan/disinkronkan.

## Acuan dan transformasi

- [Permenkes 28 Tahun 2019](https://peraturan.bpk.go.id/Details/138621/permenkes-no-28-tahun-2019), Lampiran I; [PDF resmi](https://peraturan.bpk.go.id/Download/129886/Permenkes%20Nomor%2028%20Tahun%202019.pdf). Energi, protein, lemak, karbohidrat, serat, air, zat besi, vitamin A dan D ditranskripsi dalam `AkgReference`. Umur memakai bulan kalender lengkap dari `CivilDate`. Pembandingan recall = asupan/referensi × 100%; tanpa diagnosis defisit dan tanpa koreksi berat badan. Air adalah total asupan, bukan target air putih bayi. Asupan Fe/A/D opsional; kosong berarti belum diketahui, bukan nol, dan angka negatif/nonfinite ditolak.
- [Kemenkes HK.02.02/B/576/2025](https://kesprimkom.kemkes.go.id/assets/uploads/contents/others/2025kepdirjenkesprimkom576.pdf), definisi hlm. 7, sasaran hlm. 22, standar makanan hlm. 40 dan AKG hlm. 41. Rentang PMT harian: 6–11 bulan 175–200 kkal/3,5–8 g protein; 12–23 bulan 225–275 kkal/4,5–11 g; 24–59 bulan 300–450 kkal/6–18 g. Penetapan sasaran memerlukan pemeriksaan tenaga kesehatan. Bukan resep individual atau penambahan kalori terapeutik ke AKG. Oedema, tanda bahaya, BB/PB atau BB/TB <−3 SD, atau LiLA <11,5 cm memprioritaskan rujukan. Alergi memerlukan penanganan khusus. PMT tidak mengganti makanan utama; ASI dilanjutkan. Skrining UI menggunakan data ≤31 hari (batas operasional konservatif, bukan penetapan baru durasi terapi), hasil BB/PB atau BB/TB valid dan penilaian alergi/tanda bahaya/oedema sebelum rentang ditampilkan.
- [WHO Child Growth Standards: Weight-for-age](https://www.who.int/tools/child-growth-standards/standards/weight-for-age). Panel memakai `wei` pada aset engine yang telah ada. `GrowthEngine.fromJson` memverifikasi manifest dan SHA-256 sebelum LMS dibaca. Baris `[sex, ageDays, L, M, S]`; sex 1 laki-laki, 2 perempuan. Titik standar: `M × (1 + L×S×z)^(1/L)`, atau `M×exp(S×z)` saat L nol; hanya z −3 sampai +3. Sumbu umur hari 0–1826, berat kg. Semua hari diplot tanpa interpolasi umur kalender atau ekstrapolasi. Kategori hasil tetap milik engine, tidak dihitung ulang oleh grafik. Lihat lisensi/provenance aset engine yang ada.

Nilai mikronutrien dikonfirmasi silang pada [tabel AKG Kemenkes, Juknis 2025 hlm. 41](https://kesprimkom.kemkes.go.id/assets/uploads/contents/others/2025Kepdirjenkesprimkom576.pdf), yang secara eksplisit merujuk Permenkes 28/2019:

| Umur lengkap | Fe (mg/hari) | Vitamin A (RE/hari) | Vitamin D (µg/hari) |
|---|---:|---:|---:|
| 0–5 bulan | 0,3 | 375 | 10 |
| 6–11 bulan | 11 | 400 | 10 |
| 12–47 bulan (1–3 tahun) | 7 | 400 | 15 |
| 48–83 bulan (4–6 tahun) | 10 | 450 | 15 |

RE = retinol equivalent/ekuivalen retinol, mengikuti label resmi; tidak dikonversi menjadi IU. UI menampilkan satuan dan membedakan acuan asupan dari dosis obat/suplemen/kapsul. Tidak ada dosis suplementasi yang dihitung.

## Perilaku grafik dan batas

Grafik memuat tujuh kurva WHO BB/U menurut jenis kelamin, titik pengukuran approved, legenda dan tabel pengukuran yang dapat digulir. Nilai nonfinite/tanggal rusak/umur di luar rentang/status BB/U selain valid/oedema tidak diplot. Titik tidak dihubungkan agar jeda pengukuran tidak mengesankan kunjungan bulanan teratur. Empty state dan kegagalan verifikasi aset ditampilkan eksplisit.

Ini **kurva standar WHO BB/U**, bukan salinan formulir KMS resmi Indonesia. Grafik digital menyediakan rujukan standar dan riwayat pertumbuhan, tanpa garis spesifik formulir KMS Buku KIA, perhitungan KBM per bulan atau klasifikasi naik/tidak naik otomatis. Checkbox kekhawatiran pertumbuhan harus berasal dari penilaian tenaga kesehatan; tidak disimpulkan dari perubahan berat sederhana. Referensi ini tidak mengesahkan diagnosis/terapi dan tidak mengganti pemeriksaan individu.

## Verifikasi

`flutter test --no-pub test/nutrition_test.dart test/nutrition_widget_test.dart`: 7 tes lulus. Mencakup batas umur AKG/PMT, Fe/A/D setiap awal/akhir kelompok umur, angka acuan, persentase recall energi/protein/Fe/A/D, input opsional kosong, koma desimal, NaN/infinity/negatif, prioritas rujukan/LiLA/oedema/alergi, verifikasi aset/median kedua jenis kelamin, urutan SD, penyaringan titik, empty state, data lama dan layout 390 px. Widget test menyiapkan aset di luar fake async clock; reference terverifikasi dibagi sebagai immutable cache. Tidak ada uji klinis/perangkat Android/peserta nyata dalam verifikasi ini.
