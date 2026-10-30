# Audit UI dan navigasi SI-GIBAS

Revisi 30 Oktober 2026 atas permintaan pengguna. Lingkup hanya front-end Flutter. Repository data, engine gizi, penyimpanan, akun, keamanan native dan backend tidak diubah.

## Temuan dan perbaikan

| Temuan | Perbaikan |
|---|---|
| Profil, pendataan, riwayat, detail dan grafik menumpuk pada satu halaman panjang | Beranda peran membuka halaman tugas melalui Navigator.pushNamed dan MaterialPageRoute. |
| Rincian muncul jauh di bawah tabel sehingga pengguna perlu mencari lagi | Tombol Lihat membuka halaman rincian tersendiri. Kembali menampilkan tabel dengan data terbaru. |
| Koreksi tidak membawa pengguna ke formulir yang perlu diisi | Tombol Koreksi membuka halaman pengukuran dengan isian sebelumnya, memakai handler dan validasi yang sama. |
| Pemilih profil berpotensi melebar pada layar kecil | Dropdown diperluas mengikuti batas lebar; nama panjang pada pemilih profil dipotong dengan ellipsis. |
| Header memenuhi ruang dan formulir mudah kehilangan konteks | Header memakai judul halaman dan tombol kembali; hero panjang dan badge tambahan dikeluarkan dari halaman tugas. |
| Efek tekan kartu melewati sudut kartu | Kartu menu memakai clip antiAlias untuk menahan ripple di dalam bentuk kartu. |

## Struktur halaman

Kader: beranda, profil/kontrol, tambah anak, pengukuran, riwayat dan rincian. Badan Gizi: beranda, profil/kontrol, pemeriksaan dan rincian. Pemerintah: beranda, ringkasan/ekspor, riwayat agregat dan dashboard.

Navigator bersarang berada di dalam workspace sesi. Ketika sesi berakhir, seluruh halaman turunannya ikut dilepas; tidak menambahkan sesi atau mengubah autentikasi. Isian front-end tetap dimiliki workspace agar kembali antarhalaman tidak menghapus masukan yang belum disimpan. Android back diteruskan melalui NavigatorPopHandler. Tidak memasang router atau dependensi baru.

## Verifikasi

Analisis Flutter bersih dan seluruh 157 tes lulus. Tes navigasi memeriksa push/pop dua tingkat serta persistensi isian. Tes responsif memeriksa halaman tiap peran pada 375×812, 812×375 dan 1024×768 dengan text scale 2 dan reduced motion, tanpa exception overflow. Tes alur pemeriksaan tetap memanggil repository asli; bukan mengganti logika dengan mock.

Panduan UI/UX Pro Max yang dipakai: back behavior untuk aplikasi mobile dan pedoman Flutter navigation. Rekomendasi router kompleks tidak diterapkan karena pengguna meminta push/pop dan cakupan aplikasi cukup memakai Navigator bawaan. Referensi implementasi: https://docs.flutter.dev/cookbook/navigation/navigation-basics .

Pemeriksaan ini tidak menambahkan dark mode. Pengujian widget/browser tidak menggantikan pengujian perangkat Android. Laporan hasil lama dan arsip sumber sebelumnya merupakan snapshot sebelum revisi UI ini.

## Penyempurnaan jarak dan teks

Arahan lanjutan pengguna: judul dan label dipisahkan dari kotak input, bukan floating label pada garis border. FormFieldBlock menempatkan label di atas kontrol dengan sela 8 px dan margin bawah 20 px. Judul bagian memiliki ruang bawah 20 px, kartu tabel berjarak vertikal 16–24 px, dan judul profil diletakkan di luar kartu. Instruksi riwayat/review dipadatkan menjadi tindakan inti. Label panjang dipersingkat tanpa mengubah satuan atau makna input. Keterangan AKG dan panduan PMT lengkap tetap dapat dibuka melalui expansion tile sehingga informasi kehati-hatian tidak dibuang.

Uji browser revisi akhir lulus: registrasi, pengukuran, simpan, rincian, pengajuan, kembali dengan riwayat diperbarui dan logout. Bukti dan pratinjau berada pada previews/. Pemilihan label tanggal di skrip mengikuti label baru. Pengiriman keyboard diarahkan ke input Flutter yang aktif agar tidak menimbulkan kegagalan fokus pada proxy aksesibilitas. APK release revisi ditandatangani dan diverifikasi; hash tercatat pada docs/verification/apk-candidate.json.
