// SPDX-License-Identifier: GPL-3.0-only
// Derived from WHO anthro pinned b776d8a12b1c97369c748b561159fd2ec4f4db58.
// Dart translation + individual safety/calendar/raw-category modifications.
// See assets/engine/NOTICE.md and LICENSE.md. Not diagnosis or therapy.
import 'dart:convert';
import 'dart:math' as math;

import 'sha256.dart';

enum Sex { male, female }

enum Position { recumbent, standing }

enum Oedema { yes, no, unknown }

enum Index { weightAge, heightAge, weightHeight }

enum ResultStatus {
  valid,
  missingInput,
  invalidInput,
  referenceOutOfDomain,
  unavailableOedema,
  needsReview,
}

/// Strict Gregorian civil date. UTC is used only as ordinal arithmetic;
/// callers cannot supply timestamps/timezones or silently normalized dates.
class CivilDate implements Comparable<CivilDate> {
  final int year, month, day;
  CivilDate(this.year, this.month, this.day) {
    if (year < 1 ||
        year > 9999 ||
        month < 1 ||
        month > 12 ||
        day < 1 ||
        day > _days(year, month)) {
      throw const FormatException('Invalid Gregorian civil date');
    }
  }
  factory CivilDate.parse(String value) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      throw const FormatException('Expected YYYY-MM-DD, no timestamp');
    }
    final parts = value.split('-').map(int.parse).toList();
    return CivilDate(parts[0], parts[1], parts[2]);
  }
  static int _days(int y, int m) => m == 2
      ? ((y % 4 == 0 && (y % 100 != 0 || y % 400 == 0)) ? 29 : 28)
      : ([4, 6, 9, 11].contains(m) ? 30 : 31);
  DateTime get _ordinal => DateTime.utc(year, month, day);
  int daysSince(CivilDate other) => _ordinal.difference(other._ordinal).inDays;
  CivilDate addDays(int days) {
    final value = _ordinal.add(Duration(days: days));
    return CivilDate(value.year, value.month, value.day);
  }

  CivilDate addMonths(int months) {
    final total = year * 12 + month - 1 + months;
    final y = total ~/ 12, m = total % 12 + 1;
    return CivilDate(y, m, math.min(day, _days(y, m)));
  }

  int completedMonthsAt(CivilDate date) {
    var n = (date.year - year) * 12 + date.month - month;
    if (addMonths(n).compareTo(date) > 0) n--;
    return n;
  }

  String get iso =>
      '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
  @override
  int compareTo(CivilDate other) => daysSince(other).sign;
}

class Measurement {
  final CivilDate? birth, measured;
  final Sex? sex;
  final double? weightKg, rawCm;
  final Position? rawPosition;
  final Oedema oedema;
  const Measurement({
    this.birth,
    this.measured,
    this.sex,
    this.weightKg,
    this.rawCm,
    this.rawPosition,
    this.oedema = Oedema.unknown,
  });
}

class Lms {
  final double l, m, s;
  const Lms(this.l, this.m, this.s);
}

class ScoreResult {
  final Index index;
  final String standard, reason;
  final ResultStatus status;
  final double? rawZ, officialRoundedZ;
  final bool? officialFlag, rawReviewFlag;
  final bool boundarySensitive;
  final String? categoryFinal;
  const ScoreResult._(
    this.index,
    this.standard,
    this.status,
    this.reason,
    this.rawZ,
    this.officialRoundedZ,
    this.officialFlag,
    this.rawReviewFlag,
    this.boundarySensitive,
    this.categoryFinal,
  );
  factory ScoreResult.unavailable(
    Index index,
    String standard,
    ResultStatus status,
    String reason,
  ) => ScoreResult._(
    index,
    standard,
    status,
    reason,
    null,
    null,
    null,
    null,
    false,
    null,
  );
  factory ScoreResult.scored(Index index, double z, {String standard = ''}) {
    if (!z.isFinite) {
      return ScoreResult.unavailable(
        index,
        standard,
        ResultStatus.invalidInput,
        'nonfinite_result',
      );
    }
    final rounded = GrowthEngine.roundOfficial(z);
    final official = GrowthEngine.flag(index, rounded),
        raw = GrowthEngine.flag(index, z);
    final category = GrowthEngine.category(index, z);
    return ScoreResult._(
      index,
      standard,
      official || raw ? ResultStatus.needsReview : ResultStatus.valid,
      official || raw ? 'plausibility' : 'ok',
      z,
      rounded,
      official,
      raw,
      category != GrowthEngine.category(index, rounded),
      official || raw ? null : category,
    );
  }
  bool get reviewRequired => status == ResultStatus.needsReview;
  String? get displayZ => officialRoundedZ?.toStringAsFixed(2);
}

class GrowthResult {
  final Measurement input;
  final int? ageDays, completedCalendarMonths;
  final double? referenceAgeMonths, correctedCm, correctionCm;
  final Position? targetPosition;
  final Map<Index, ScoreResult> results;
  final Map<String, String> provenance;
  GrowthResult(
    this.input,
    this.ageDays,
    this.completedCalendarMonths,
    this.referenceAgeMonths,
    this.correctedCm,
    this.correctionCm,
    this.targetPosition,
    Map<Index, ScoreResult> results,
    this.provenance,
  ) : results = Map.unmodifiable(results);
}

class GrowthEngine {
  static const whoCommit = 'b776d8a12b1c97369c748b561159fd2ec4f4db58';
  static const tableSHA256 =
      '656d7ca5a100e50af61008d7c72a59468c16c5a2affd51010dfc77c8bcb5fb7b';
  final Map<String, Map<int, Map<int, Lms>>> _tables;
  final Map<String, String> provenance;
  GrowthEngine._(this._tables, this.provenance);
  factory GrowthEngine.fromJson(String tablesJson, String manifestJson) {
    final manifest = jsonDecode(manifestJson) as Map<String, dynamic>;
    if (manifest['schema'] != 1 ||
        manifest['engineVersion'] != '0.1.0' ||
        manifest['whoCommit'] != whoCommit ||
        manifest['tablesSHA256'] != tableSHA256 ||
        sha256(utf8.encode(tablesJson)) != tableSHA256) {
      throw const FormatException(
        'Unsupported or corrupt engine tables/manifest',
      );
    }
    final decoded = jsonDecode(tablesJson) as Map<String, dynamic>;
    final tables = <String, Map<int, Map<int, Lms>>>{};
    const specs = {
      'wei': (0, 1826, 1),
      'len': (0, 1826, 1),
      'wfl': (450, 1100, 10),
      'wfh': (650, 1200, 10),
    };
    for (final name in specs.keys) {
      final spec = specs[name]!;
      final sexes = <int, Map<int, Lms>>{1: {}, 2: {}};
      for (final row in decoded[name] as List) {
        final sex = (row[0] as num).toInt(),
            key = ((row[1] as num) * spec.$3).round();
        if (!sexes.containsKey(sex) ||
            key < spec.$1 ||
            key > spec.$2 ||
            sexes[sex]!.containsKey(key)) {
          throw const FormatException('Invalid table row');
        }
        sexes[sex]![key] = Lms(
          (row[2] as num).toDouble(),
          (row[3] as num).toDouble(),
          (row[4] as num).toDouble(),
        );
      }
      for (final rows in sexes.values) {
        if (rows.length != spec.$2 - spec.$1 + 1) {
          throw const FormatException('Incomplete table');
        }
      }
      tables[name] = Map.unmodifiable({
        for (final sex in sexes.keys)
          sex: Map<int, Lms>.unmodifiable(sexes[sex]!),
      });
    }
    return GrowthEngine._(
      Map.unmodifiable(tables),
      Map.unmodifiable({
        'engineVersion': '0.1.0',
        'whoCommit': whoCommit,
        'tableHash': tableSHA256,
        'tableManifestHash': sha256(utf8.encode(manifestJson)),
        'agePolicy': 'civil-under5-clamp-original-dob-v1',
        'positionPolicy': 'WHO-731-v1',
        'classificationPolicy': 'permenkes-raw-v1',
        'precisionPolicy': 'raw-plus-R-nearest-even-2-v1',
        'licenseProvenance': 'GPL-3-derived; assets/engine/NOTICE.md; distribution component-rights review pending',
      }),
    );
  }

  static double zscore(double y, Lms t, {required bool adjusted}) {
    if (!y.isFinite ||
        y <= 0 ||
        !t.l.isFinite ||
        !t.m.isFinite ||
        t.m <= 0 ||
        !t.s.isFinite ||
        t.s <= 0) {
      return double.nan;
    }
    final z = t.l == 0
        ? math.log(y / t.m) / t.s
        : (math.pow(y / t.m, t.l) - 1) / (t.s * t.l);
    double q(double sd) => t.l == 0
        ? t.m * math.exp(t.s * sd)
        : t.m * math.pow(1 + t.l * t.s * sd, 1 / t.l);
    if (adjusted && z > 3) return 3 + (y - q(3)) / (q(3) - q(2));
    if (adjusted && z < -3) return -3 + (y - q(-3)) / (q(-2) - q(-3));
    return z;
  }

  /// R fround semantics for two decimal places: compare distances in original
  /// double space, ties nearest even. No epsilon that moves category boundaries.
  static double roundOfficial(double x) {
    if (!x.isFinite) throw ArgumentError.value(x, 'x', 'finite score required');
    final sign = x < 0 ? -1 : 1, value = x.abs();
    if (value >= 1e14) return x; // already beyond useful fractional precision
    final lower = (value * 100).floor();
    final down = lower / 100, up = (lower + 1) / 100;
    final d1 = value - down, d2 = up - value;
    return sign * ((d2 < d1 || (d1 == d2 && lower.isOdd)) ? up : down);
  }

  static bool flag(Index i, double z) => switch (i) {
    Index.weightAge => z < -6 || z > 5,
    Index.heightAge => z.abs() > 6,
    Index.weightHeight => z.abs() > 5,
  };
  static String category(Index i, double z) {
    if (!z.isFinite) throw ArgumentError.value(z, 'z', 'finite score required');
    return switch (i) {
      Index.weightAge =>
        z < -3
            ? 'berat badan sangat kurang'
            : z < -2
            ? 'berat badan kurang'
            : z <= 1
            ? 'berat badan normal'
            : 'risiko berat badan lebih',
      Index.heightAge =>
        z < -3
            ? 'sangat pendek'
            : z < -2
            ? 'pendek'
            : z <= 3
            ? 'normal'
            : 'tinggi',
      Index.weightHeight =>
        z < -3
            ? 'gizi buruk'
            : z < -2
            ? 'gizi kurang'
            : z <= 1
            ? 'gizi baik'
            : z <= 2
            ? 'berisiko gizi lebih'
            : z <= 3
            ? 'gizi lebih'
            : 'obesitas',
    };
  }

  GrowthResult evaluate(Measurement input) {
    final birth = input.birth, date = input.measured;
    int? days, months;
    double? refMonths, corrected, correction;
    Position? target;
    String? global;
    var globalStatus = ResultStatus.missingInput;
    if (birth == null || date == null) {
      global = 'missing_age';
    } else {
      days = date.daysSince(birth);
      if (days < 0) {
        global = 'measurement_before_birth';
        globalStatus = ResultStatus.invalidInput;
      } else {
        months = birth.completedMonthsAt(date);
        refMonths = days / 30.4375;
        if (months >= 60) {
          global = 'fifth_birthday';
          globalStatus = ResultStatus.referenceOutOfDomain;
        } else if (days > 1826 || refMonths >= 60) {
          global = 'reference_age_domain';
          globalStatus = ResultStatus.referenceOutOfDomain;
        }
      }
    }
    if (global == null && input.sex == null) global = 'missing_sex';
    final output = <Index, ScoreResult>{};
    if (global != null) {
      for (final i in Index.values) {
        output[i] = ScoreResult.unavailable(i, '', globalStatus, global);
      }
    } else {
      final age = days!, sex = input.sex == Sex.male ? 1 : 2;
      target = age < 731 ? Position.recumbent : Position.standing;
      final heightName = age < 731 ? 'wfl' : 'wfh';
      String? heightReason;
      var heightStatus = ResultStatus.missingInput;
      if (input.rawCm == null) {
        heightReason = 'missing_length';
      } else if (!input.rawCm!.isFinite || input.rawCm! <= 0) {
        heightReason = 'invalid_length';
        heightStatus = ResultStatus.invalidInput;
      } else if (input.rawPosition == null) {
        heightReason = 'missing_position';
      } else if (input.rawPosition == Position.standing && refMonths! < 9) {
        heightReason = 'standing_under9months';
        heightStatus = ResultStatus.needsReview;
      } else {
        correction = input.rawPosition == target
            ? 0.0
            : (age < 731 ? 0.7 : -0.7);
        corrected = input.rawCm! + correction;
        if (corrected <= 0) {
          heightReason = 'invalid_corrected_length';
          heightStatus = ResultStatus.invalidInput;
        }
      }
      String? weightReason;
      var weightStatus = ResultStatus.missingInput;
      if (input.weightKg == null) {
        weightReason = 'missing_weight';
      } else if (!input.weightKg!.isFinite || input.weightKg! <= 0) {
        weightReason = 'invalid_weight';
        weightStatus = ResultStatus.invalidInput;
      } else if (input.oedema == Oedema.unknown) {
        weightReason = 'unknown_oedema';
      } else if (input.oedema == Oedema.yes) {
        weightReason = 'oedema';
        weightStatus = ResultStatus.unavailableOedema;
      }
      for (final i in Index.values) {
        final name = i == Index.weightAge
            ? 'wei'
            : i == Index.heightAge
            ? 'len'
            : heightName;
        if (i != Index.heightAge && weightReason != null) {
          output[i] = ScoreResult.unavailable(
            i,
            name,
            weightStatus,
            weightReason,
          );
          continue;
        }
        if (i != Index.weightAge && heightReason != null) {
          output[i] = ScoreResult.unavailable(
            i,
            name,
            heightStatus,
            heightReason,
          );
          continue;
        }
        Lms? t;
        if (i == Index.weightHeight) {
          final cm = corrected!;
          final min = age < 731 ? 45 : 65, max = age < 731 ? 110 : 120;
          if (cm < min || cm > max) {
            output[i] = ScoreResult.unavailable(
              i,
              name,
              ResultStatus.referenceOutOfDomain,
              'length_domain',
            );
            continue;
          }
          // Match R truncation, interpolation of LMS (not Z), including
          // its floating point fraction; no endpoint clamp/extrapolation.
          final low = (cm * 10).truncate(), high = (cm * 10 + 1).truncate();
          final fraction = (cm - low / 10) / .1;
          final a = _tables[name]![sex]![low], b = _tables[name]![sex]![high];
          if (a != null && (fraction <= 0 || b != null)) {
            t = fraction > 0
                ? Lms(
                    a.l + fraction * (b!.l - a.l),
                    a.m + fraction * (b.m - a.m),
                    a.s + fraction * (b.s - a.s),
                  )
                : a;
          }
        } else {
          t = _tables[name]![sex]![age];
        }
        if (t == null) {
          output[i] = ScoreResult.unavailable(
            i,
            name,
            ResultStatus.referenceOutOfDomain,
            'missing_table_row',
          );
          continue;
        }
        final y = i == Index.heightAge ? corrected! : input.weightKg!;
        output[i] = ScoreResult.scored(
          i,
          zscore(y, t, adjusted: i != Index.heightAge),
          standard: name,
        );
      }
    }
    return GrowthResult(
      input,
      days,
      months,
      refMonths,
      corrected,
      correction,
      target,
      output,
      provenance,
    );
  }
}
