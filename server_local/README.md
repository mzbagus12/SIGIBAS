# Backend lokal SI-GIBAS — data sintetis saja

Server hanya bind `127.0.0.1`; tidak memakai layanan eksternal. `synthetic:true` bukan bukti data benar-benar sintetis. Jangan gunakan identitas, NIK/foto, pengukuran atau catatan nyata. SQLite server tidak dienkripsi; simpan database/private key di folder lokal yang diabaikan Git.

Jalankan: `python server.py --database PATH_DATABASE_SINTETIS`. Uji: `python -m unittest -v`. Browser demo harus pada `http://127.0.0.1:8767`. Android memakai `adb reverse tcp:8768 tcp:8768`.

## Sinkronisasi dan akun lokal

`POST /sync-login` menerima `user` dan `pin`; bootstrap sintetis adalah kader/1111, gizi/2222, pemerintah/3333. PIN disimpan PBKDF2-SHA256 dengan salt acak dan 120000 iterasi, bukan plaintext. Login salah lima kali memberi jeda 30 detik. Token acak berlaku 30 menit dalam memori server. Header role tidak menentukan izin endpoint sync. `/sync-password` dengan token/oldPin/newPin (8–128 karakter) mengganti PIN dan mencabut seluruh sesi akun; `/sync-logout` mencabut token. PIN ini terpisah dari login tampilan demo offline yang tetap publik.

`POST /sync`: token, synthetic:true, changes, limit opsional (1–100), cursor opsional. Record child/revision/visit memakai compare-and-swap versi dan operation ID stabil. Transaksi batch seluruhnya rollback ketika satu perubahan tidak valid. Batas 100 perubahan, 32 KiB per record; klien mengirim batch25 dan meminta halaman25 agar sesuai batas respons Android 1 MiB. Pagination berdasarkan key; sinkronisasi berikutnya mengambil perubahan yang terjadi di antara halaman. Belum snapshot read lintas halaman.

Klien mempertahankan data lokal dan pilihan konflik secara persisten. Pilihan server menyimpan salinan lokal di audit; pilihan lokal profil/jadwal melakukan rebase versi. Pilihan lokal pengukuran membuat draft koreksi baru saat server sudah draft/approved/rejected; server pending harus direview dahulu. Revisi historis yang telah direview diunggah Kader sebagai pending dan memerlukan sesi Gizi untuk konfirmasi review; status lokal asli dipertahankan. Retry setelah ACK hilang menarik versi server dan tidak menggandakan operasi.

Pemerintah tidak menerima/mengubah individu: /sync mengembalikan records kosong, aggregate dan dashboard per bulan/wilayah. Agregat berunit observasi pengukuran approved efektif, bukan jumlah anak unik. Hasil gizi masih berasal dari klien; `clinicalValidation:false` menegaskan server **belum menghitung ulang hasil klinis**. Server memvalidasi bentuk pengukuran, tanggal, angka positif finite, peran, perubahan review dan rantai revisi linear.

`POST /security-events` membutuhkan token dan events berisi hanya eventId, atDevice, findings enum. ACK idempotent per akun/eventId, menolak penggunaan ulang dengan isi berbeda. Tidak menerima ID perangkat atau payload bebas. Waktu perangkat tidak tepercaya. Ini pencatatan lokal, bukan layanan pemantauan eksternal.

Endpoint lama `/revisions`, `/review`, GET `/aggregate` tetap demonstrasi header role yang dapat dipalsukan; jangan gunakan sebagai otorisasi. Tidak ada akun produksi, pemulihan PIN terkelola, atau keamanan data nyata.

## TLS loopback opsional

`python server.py --database PATH --tls-cert CERT_PEM --tls-key KEY_PEM` mengaktifkan TLS minimal1.2. Cert/private key harus dibuat lokal, jangan commit. Android dapat dibangun dengan `--dart-define=SIGIBAS_SERVER_URL=https://127.0.0.1:8768 --dart-define=SIGIBAS_TLS_SHA256=SHA256_DER_64_HEX`. Transport Android HTTPS memakai trust store kosong dan menerima hanya sertifikat yang DER SHA256-nya tepat sama dengan pin **sebelum POST dikirim**; redirect ditolak. HTTP tetap hanya untuk build debug. Android release memerlukan URL HTTPS+pin valid untuk mengaktifkan sinkronisasi.

Web memakai URL define yang sama, tetapi kepercayaan sertifikat ditangani browser; tidak ada pinning aplikasi browser. Origin web demo masih http localhost8767. HTTPS/pinning transport tidak mengubah sifat akun publik/data sintetis atau membuktikan keamanan produksi.
