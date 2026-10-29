import 'package:flutter_test/flutter_test.dart';
import 'package:sigibas_rasp/mvp/kms_trend.dart';

void main() {
  test('KBM Buku KIA 2024 menurut umur dan jenis kelamin', () {
    for (var month = 1; month <= 60; month++) {
      final male = month <= 6
          ? [800, 900, 800, 600, 500, 400][month - 1]
          : month == 7
          ? 400
          : month <= 11
          ? 300
          : 200;
      final female = month <= 6
          ? [800, 900, 800, 600, 500, 400][month - 1]
          : month <= 10
          ? 300
          : 200;
      expect(MonthlyGrowth.minimum('male', month), male);
      expect(MonthlyGrowth.minimum('female', month), female);
    }
    expect(MonthlyGrowth.minimum('male', 0), isNull);
    expect(MonthlyGrowth.minimum('female', 61), isNull);
  });
  test('N tepat KBM, T di bawah KBM dan jeda/duplikat tidak dinilai', () {
    final samples = <Map<String, dynamic>>[
      {'date': '2026-01-01', 'kg': 3.0},
      {'date': '2026-02-01', 'kg': 3.8},
      {'date': '2026-03-01', 'kg': 4.6},
      {'date': '2026-05-01', 'kg': 5.7},
    ];
    final rows = MonthlyGrowth.assess('2026-01-01', 'male', samples);
    expect(rows[0].status, 'Belum dapat dinilai');
    expect(rows[1].status, 'Naik (N)');
    expect(rows[1].gainGrams, 800);
    expect(rows[2].status, 'Tidak naik (T)');
    expect(rows[2].minimumGrams, 900);
    expect(rows[3].status, 'Jadwal tidak sebanding');
    samples.insert(2, {'date': '2026-02-10', 'kg': 3.9});
    expect(
      MonthlyGrowth.assess('2026-01-01', 'male', samples)[3].status,
      'Jadwal tidak sebanding',
    );
  });
}
