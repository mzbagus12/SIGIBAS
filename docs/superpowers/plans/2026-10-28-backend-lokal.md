# Backend lokal sintetis Tahap 4

Tujuan: menguji batas server dan penyimpanan data sintetis secara lokal, dengan transaksi idempotent, validasi revisi, penolakan beralasan, persetujuan dan ringkasan anonim. Implementasi adalah demonstrasi; role uji bukan autentikasi produksi.

1. Tambahkan tes layanan berbasis SQLite sementara untuk pengiriman, idempotensi, penolakan data non-sintetis dan konflik, serta transaksi review.
2. Implementasikan layanan yang hanya bind ke loopback, membatasi payload dan menampilkan kegagalan eksplisit; jangan membuka jaringan publik.
3. Uji endpoint dan perilaku server, lalu dokumentasikan batas; integrasi Flutter perlu dilakukan dan diuji terpisah.
