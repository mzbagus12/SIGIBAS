# Dashboard Pemerintah dan ekspor sintetis

Implementasi F-08 menerima agregat saja. Integrasi controller lokal: `GovernmentDashboard(data: buildGovernmentDashboard(repo.state))`; jangan meneruskan `repo.state` ke widget. Server boleh mengirim objek dashboard dengan kontrak yang sama. Widget tidak membutuhkan repository atau layanan peta.

## Kontrak data

`buildGovernmentDashboard` menelusuri leaf rantai revisi ke persetujuan terakhir dan mengelompokkan satu revisi efektif per pengukuran. Koreksi draft/pending/rejected mempertahankan persetujuan lama. Koreksi approved menggantikannya. Status hasil selain `valid` tidak menambah penyebut. Unit hitung adalah **observasi pengukuran**, bukan anak unik; satu anak dengan dua pengukuran dapat dihitung dua kali. Bulan berasal dari tanggal pengukuran, bukan waktu persetujuan.

Keluaran hanya berisi `unit`, `cells` (`month`, `village`, `aggregate`) dan `areas` (`village`, `x`, `y`). Setiap aggregate memiliki `weightAge`, `heightAge`, `weightHeight` dengan `denominator` dan `categories`. Nama, NIK, ID anak/pengukuran/revisi, tanggal lahir, nilai BB/TB serta catatan tidak disalin. Tanpa wilayah memakai label `Wilayah belum diisi`.

Tampilan meliputi tren stunting menurut bulan (jumlah/persen), pie kategori indikator, bar penyebut valid per kelurahan, peta heatmap koordinat lokal dan tabel prioritas yang dapat diurutkan. Bulan, kelurahan dan indikator dapat dipilih. Tren mempertahankan semua bulan untuk konteks; filter bulan membatasi pie/bar/peta/prioritas. Stunting dihitung dari kategori **pendek + sangat pendek** pada heightAge. Ini ringkasan observasi sintetis, bukan prevalensi populasi atau rekomendasi klinis.

Peta menggunakan titik pusat wilayah dengan koordinat **fiktif** dalam km timur/utara. Posisi dibuat deterministik dari daftar wilayah yang diurutkan. Peta bukan peta administratif nyata, tidak memakai GPS, koordinat anak, API peta atau telemetry. Warna/radial heat menunjukkan persen stunting; abu-abu berarti tidak ada penyebut valid. Titik dapat diketuk untuk filter kelurahan. Koordinat perlu diganti dengan geometri wilayah terverifikasi bila kelak ada cakupan nyata yang diizinkan; tidak ada klaim akurasi geografis untuk demonstrasi ini.

## Ekspor F-09

Excel OOXML `.xlsx`: sheet `Agregat` berisi Indikator, Kategori, Jumlah, Penyebut, Persen. Jumlah/penyebut adalah integer, persen angka desimal skala 0–100 (satu desimal). Sheet `Keterangan` menjelaskan unit, koreksi, pembulatan dan data sintetis. Kategori adalah TextCellValue sehingga teks diawali `=` tidak menjadi rumus. Header diberi warna/bold dan lebar kolom diatur. Penyebut nol ditulis eksplisit, agregat inkonsisten ditolak sebelum pembuatan berkas.

PDF A4 memiliki judul, unit, tabel dengan kepala berulang, margin 32 pt, footer nomor halaman serta label data sintetis. Keduanya bukan format impor resmi SSGI/e-PPGBM dan tidak memuat identitas anak. Tombol aplikasi masih mengekspor ringkasan keseluruhan; filter dashboard tidak mengubah cakupan ekspor.

Browser memakai Blob download untuk Excel dan printing sharePdf untuk PDF. Android Excel memakai MethodChannel `sigibas/reports`, metode `shareExcel`, payload `bytes` (Uint8List), `name` (basename dibuat aplikasi), `mime` (OOXML). Adapter native harus menulis cache privat lalu membuka ACTION_SEND dengan content URI FileProvider dan izin baca sementara; respons `shared` hanya menyatakan lembar berbagi dibuka. Penyimpanan/kirim akhirnya bergantung pilihan pengguna. Kesalahan native diteruskan ke UI untuk dicoba ulang. Desktop IO masih menulis direktori dokumen aplikasi. PDF memakai printing/sharePdf yang tersedia.

## Bukti verifikasi

`test/mvp/government_dashboard_test.dart`: koreksi tanpa hitung ganda, penyebut tiap indikator, dua observasi anak yang sama, kategori stunting lokal, batas privasi, koordinat sintetis, cycle, keadaan kosong, filter viewport 390x844 dan empty viewport 320x640. `test/mvp/report_test.dart`: decode OOXML, angka/rumus aman, penolakan agregat salah, penyebut nol dan fixture PDF/Excel.

29 Oktober 2026: 11 tes fokus lulus (5 dashboard, 5 laporan, 1 ringkasan lama); analisis enam berkas fokus tanpa temuan. Parser independen pypdf/openpyxl membaca PDF 1 halaman, Excel 10 baris numerik dan dua sheet; hasil `export-qa/parser-results.json`. Poppler merender PDF normal dan kosong. Inspeksi visual normal: judul/tabel/footer terbaca, 10 baris lengkap, tidak terpotong. Empty PDF juga memperlihatkan judul, penjelasan dan pesan kosong yang terbaca; potongan header tersimpan untuk pemeriksaan. Fixture dan PNG disimpan di `export-qa/`. Peringatan font Helvetica/Symbol muncul pada generator/Poppler; karakter Indonesia pada fixture ini adalah ASCII dan berhasil dirender/diekstrak. Font lintas bahasa belum dijamin.

Uji klik unduh browser dan lembar berbagi Android perlu dilakukan pada build terintegrasi. Tidak ada hasil Android nyata yang diklaim. Bukan uji calon pengguna, validasi klinis atau kelulusan seluruh Tahap 4.
