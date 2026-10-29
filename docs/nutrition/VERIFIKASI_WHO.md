# Verifikasi teknis indeks pertumbuhan

Tanggal pemeriksaan: 29 Oktober 2026. Semua kasus memakai data sintetis. Ini verifikasi perangkat lunak dengan rujukan numerik resmi, bukan pemeriksaan pasien atau validasi klinis.

## Metode

Enam puluh kasus pada test/fixtures/who_published_lms_cases.json menggunakan 12 baris LMS yang dibaca dari PDF WHO di bawah. Nilai masukan dihasilkan terpisah menggunakan Python math.pow, dengan x = M * (1 + L*S*z)^(1/L), pada z -2.4, -1, 0, 1.4, dan 2.5. Nilai fixture tidak dihitung oleh kode Dart atau dibaca dari aset aplikasi. Tes menjalankan engine asli, membandingkan rawZ dengan z acuan pada toleransi absolut 0.00001, dan membandingkan kategori Indonesia. Batas kategori diperiksa terhadap Permenkes 2/2020 halaman tercetak 14. Kasus dipilih menjauhi ambang tepat agar galat floating point tidak mengaburkan pengujian angka acuan; pengujian batas tetap ada pada engine_test.dart.

| Indeks | Kelamin | Acuan hari/ukuran | L | M | S |
|---|---|---|---:|---:|---:|
| BB/U | L | hari 0 | .3487 | 3.3464 | .14602 |
| BB/U | P | hari 0 | .3809 | 3.2322 | .14171 |
| BB/U | L | hari 91 | .1740 | 6.3690 | .11732 |
| BB/U | P | hari 91 | .0407 | 5.8393 | .12622 |
| PB/U | L | hari 0 | 1 | 49.8842 | .03795 |
| PB/U | P | hari 0 | 1 | 49.1477 | .03790 |
| PB/U | L | hari 91 | 1 | 61.4013 | .03329 |
| PB/U | P | hari 91 | 1 | 59.7773 | .03520 |
| BB/PB | L | 50 cm | -.3521 | 3.3278 | .08890 |
| BB/PB | P | 50 cm | -.3833 | 3.3518 | .09068 |
| BB/TB | L | 75 cm | -.3521 | 9.6440 | .08303 |
| BB/TB | P | 75 cm | -.3833 | 9.2786 | .08996 |

BB/PB diuji pada hari 0 dengan posisi berbaring; BB/TB pada hari 731 dengan posisi berdiri. Minggu 13 pada tabel WHO berarti hari 91. Tidak ada interpolasi umur pada kasus acuan ini. Parameter LMS disalin dari publikasi, bukan diverifikasi hanya berdasarkan manifest internal.

## Sumber yang diperiksa

- WHO BB/U laki-laki minggu 0 dan 13: https://cdn.who.int/media/docs/default-source/child-growth/child-growth-standards/indicators/weight-for-age/wfa-boys-0-13-zscores.pdf
- WHO BB/U perempuan minggu 0 dan 13: https://cdn.who.int/media/docs/default-source/child-growth/child-growth-standards/indicators/weight-for-age/wfa-girls-0-13-zscores.pdf
- WHO PB/U laki-laki: https://cdn.who.int/media/docs/default-source/child-growth/child-growth-standards/indicators/length-height-for-age/lfa_boys_0_13_zscores.pdf
- WHO PB/U perempuan: https://cdn.who.int/media/docs/default-source/child-growth/child-growth-standards/indicators/length-height-for-age/lfa_girls_0_13_zscores.pdf
- WHO BB/PB laki-laki: https://cdn.who.int/media/docs/default-source/child-growth/child-growth-standards/indicators/weight-for-length-height/wfl-boys-0-2-zscores.pdf
- WHO BB/PB perempuan: https://cdn.who.int/media/docs/default-source/child-growth/child-growth-standards/indicators/weight-for-length-height/wfl-girls-0-2-zscores.pdf
- WHO BB/TB laki-laki: https://cdn.who.int/media/docs/default-source/child-growth/child-growth-standards/indicators/weight-for-length-height/wfh-boys-2-5-zscores.pdf
- WHO BB/TB perempuan: https://cdn.who.int/media/docs/default-source/child-growth/child-growth-standards/indicators/weight-for-length-height/wfh-girls-2-5-zscores.pdf
- Kementerian Kesehatan, kategori dan ambang: https://jdih.kemkes.go.id/storage/documents/pdfs/2020permenkes002.pdf

## Hasil dan cakupan

Seluruh 60 kasus acuan lulus. Bukti dapat direproduksi melalui flutter test --no-pub test/engine/published_who_test.dart. Cakupan ini tidak menguji seluruh baris standar, semua umur, nilai ekstrem, AKG/PMT atau tata laksana klinis. Tes engine yang sudah ada mencakup batas kategori, oedema, tanggal, dan peralihan posisi. Keduanya perlu dibaca bersama, bukan sebagai pengesahan klinis.
