# Penyempurnaan antarmuka Tahap 4

Tujuan: membuat alur MVP lebih mudah dipahami tanpa mengubah perhitungan, status, histori, keamanan yang disimulasikan, atau sumber data.

1. Tambahkan pemeriksaan widget untuk label indikator dan ringkasan status berbahasa Indonesia, serta memastikan data teknis tetap dapat dilihat melalui detail.
2. Ubah `lib/mvp/ui.dart`: label peran dan indikator, ringkasan hasil/masukan, dashboard kategori terbaca, pilihan form yang mudah dipahami, keyboard angka. Letakkan data teknis pada bagian detail yang dapat dibuka. Pertahankan penjelasan data sintetis dan batas keamanan.
3. Jalankan tes widget, seluruh tes dan analisis; bangun web dan uji skenario browser ukuran ponsel. Sesuaikan harness agar memeriksa label baru tanpa menghapus pemeriksaan fungsional.
4. Catat hasil, temuan dan batas uji dalam matriks Tahap 4. Uji dengan calon pengguna membutuhkan peserta nyata dan tidak boleh direkayasa.
