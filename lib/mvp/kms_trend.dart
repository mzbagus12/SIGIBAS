import '../engine/engine.dart';

class MonthlyGrowth {
  final String date, status;
  final int? gainGrams, minimumGrams;
  const MonthlyGrowth(
    this.date,
    this.status,
    this.gainGrams,
    this.minimumGrams,
  );
  static int? minimum(String sex, int month) {
    if (!['male', 'female'].contains(sex) || month < 1 || month > 60) {
      return null;
    }
    if (month <= 6) return [800, 900, 800, 600, 500, 400][month - 1];
    if (sex == 'male' && month == 7) return 400;
    if (month <= (sex == 'male' ? 11 : 10)) return 300;
    return 200;
  }

  static List<MonthlyGrowth> assess(
    String birth,
    String sex,
    List<Map<String, dynamic>> samples,
  ) {
    final dob = CivilDate.parse(birth);
    final sorted = List<Map<String, dynamic>>.from(samples)
      ..sort((a, b) => (a['date'] as String).compareTo(b['date']));
    final counts = <int, int>{};
    for (final sample in sorted) {
      final date = CivilDate.parse(sample['date']);
      final month = dob.completedMonthsAt(date);
      counts[month] = (counts[month] ?? 0) + 1;
    }
    final result = <MonthlyGrowth>[];
    for (var i = 0; i < sorted.length; i++) {
      final current = sorted[i], date = CivilDate.parse(current['date']);
      final month = dob.completedMonthsAt(date), kbm = minimum(sex, month);
      if (i == 0 || kbm == null) {
        result.add(MonthlyGrowth(date.iso, 'Belum dapat dinilai', null, kbm));
        continue;
      }
      final previous = sorted[i - 1],
          previousDate = CivilDate.parse(previous['date']);
      final previousMonth = dob.completedMonthsAt(previousDate);
      final calendarGap =
          (date.year - previousDate.year) * 12 +
          date.month -
          previousDate.month;
      if (month - previousMonth != 1 ||
          calendarGap != 1 ||
          counts[month] != 1 ||
          counts[previousMonth] != 1) {
        result.add(
          MonthlyGrowth(date.iso, 'Jadwal tidak sebanding', null, kbm),
        );
        continue;
      }
      final gain =
          ((current['kg'] as num) * 1000).round() -
          ((previous['kg'] as num) * 1000).round();
      result.add(
        MonthlyGrowth(
          date.iso,
          gain >= kbm ? 'Naik (N)' : 'Tidak naik (T)',
          gain,
          kbm,
        ),
      );
    }
    return result;
  }
}
