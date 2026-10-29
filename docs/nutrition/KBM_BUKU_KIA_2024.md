# Pemantauan kenaikan berat badan

Sumber: Buku KIA 2024 Kementerian Kesehatan, halaman tercetak 131–132 (laki-laki) dan 143–144 (perempuan). PDF resmi: https://kesprimkom.kemkes.go.id/assets/uploads/contents/others/Buku_KIA_2024.pdf . Halaman grafik diperiksa visual dari PDF, bukan hanya hasil OCR. PDF disimpan sementara pada .dart_tool/references/ untuk pemeriksaan.

KBM bulan 1–6 untuk kedua kelamin adalah 800, 900, 800, 600, 500, 400 gram. Laki-laki bulan 7: 400 gram, bulan 8–11: 300 gram, bulan 12–60: 200 gram. Perempuan bulan 7–10: 300 gram dan bulan 11–60: 200 gram. Penimbangan pertama tidak diberi N/T.

Implementasi kms_trend.dart membandingkan dua bulan kalender berurutan yang juga memiliki selisih satu bulan usia lengkap. Usia ditentukan dari tanggal lahir. Data ganda pada usia yang sama atau jeda bulan ditandai tidak sebanding, tanpa membagi KBM secara prorata. Berat dikonversi ke gram bulat sebelum selisih dihitung. Kenaikan yang memenuhi KBM diberi N dan yang kurang diberi T. Riwayat mengambil persetujuan efektif, menyaring oedema dan hasil BB/U tidak valid seperti grafik yang sudah ada. Hasil ditampilkan dalam tabel setelah grafik WHO.

Buku KIA menyatakan KBM membantu ketika arah kurva meragukan. Aplikasi menampilkan hasil metode KBM, bukan menggantikan pemeriksaan arah kurva oleh petugas. Hasil T memerlukan tindak lanjut; tabel ini tidak menjadi penetapan otomatis PMT atau diagnosis. Grafik menggunakan kurva standar WHO, bukan gambar formulir resmi.

Tes memeriksa tabel menurut jenis kelamin untuk bulan 1–60, kesamaan kenaikan dengan KBM, kenaikan kurang, penimbangan pertama, duplikasi dan bulan terlewat. Integrasi juga diuji bersama panel gizi pada layout sempit.
