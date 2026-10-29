import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sigibas_rasp/engine/engine.dart';
import 'package:sigibas_rasp/engine/sha256.dart';

void main() {
  late GrowthEngine engine;
  setUpAll(() {
    engine = GrowthEngine.fromJson(
      File('assets/engine/tables.json').readAsStringSync(),
      File('assets/engine/manifest.json').readAsStringSync(),
    );
  });
  test(
    'civil dates reject rollover, timestamps and missing age explicitly',
    () {
      expect(() => CivilDate.parse('2023-02-29'), throwsFormatException);
      expect(
        () => CivilDate.parse('2024-01-01T00:00:00Z'),
        throwsFormatException,
      );
      expect(() => CivilDate(2024, 13, 1), throwsFormatException);
      final r = engine.evaluate(const Measurement(sex: Sex.male));
      expect(r.results.values.every((x) => x.reason == 'missing_age'), isTrue);
    },
  );
  test('original DOB calendar clamp, leap anniversary, no month drift', () {
    final b = CivilDate(2023, 1, 31);
    expect(b.addMonths(1).iso, '2023-02-28');
    expect(b.addMonths(2).iso, '2023-03-31');
    expect(b.completedMonthsAt(CivilDate(2023, 3, 30)), 1);
    expect(b.completedMonthsAt(CivilDate(2023, 3, 31)), 2);
    expect(CivilDate(2020, 2, 29).addMonths(60).iso, '2025-02-28');
  });
  Measurement at(
    int day, {
    double? kg = 10,
    double? cm = 85,
    Position? pos = Position.recumbent,
    Sex? sex = Sex.male,
    Oedema oedema = Oedema.no,
  }) => Measurement(
    birth: CivilDate(2020, 1, 1),
    measured: CivilDate(2020, 1, 1).addDays(day),
    sex: sex,
    weightKg: kg,
    rawCm: cm,
    rawPosition: pos,
    oedema: oedema,
  );
  test('day730/731 correction once and raw retained', () {
    final a = engine.evaluate(at(730, pos: Position.standing));
    final b = engine.evaluate(at(731));
    expect(a.correctedCm, 85.7);
    expect(a.correctionCm, .7);
    expect(a.input.rawCm, 85);
    expect(b.correctedCm, 84.3);
    expect(b.correctionCm, -.7);
    expect(engine.evaluate(a.input).correctedCm, a.correctedCm);
    expect(a.referenceAgeMonths, 730 / 30.4375);
  });
  test('fifth birthday, day1826/1827 and dates earlier than DOB', () {
    expect(engine.evaluate(at(1826)).results[Index.weightAge]!.rawZ, isNotNull);
    expect(
      engine.evaluate(at(1827)).results[Index.weightAge]!.reason,
      'fifth_birthday',
    );
    final early = engine.evaluate(
      Measurement(
        birth: CivilDate(2024, 1, 2),
        measured: CivilDate(2024, 1, 1),
        sex: Sex.male,
      ),
    );
    expect(early.results[Index.weightAge]!.reason, 'measurement_before_birth');
    final leap = engine.evaluate(
      Measurement(
        birth: CivilDate(2020, 2, 29),
        measured: CivilDate(2025, 2, 28),
        sex: Sex.male,
      ),
    );
    expect(leap.results[Index.weightAge]!.reason, 'fifth_birthday');
  });
  test('partial availability, oedema and c9 safer policy', () {
    expect(
      engine.evaluate(at(400, cm: null)).results[Index.weightAge]!.rawZ,
      isNotNull,
    );
    expect(
      engine.evaluate(at(400, kg: null)).results[Index.heightAge]!.rawZ,
      isNotNull,
    );
    expect(
      engine.evaluate(at(400, pos: null)).results[Index.heightAge]!.reason,
      'missing_position',
    );
    expect(
      engine
          .evaluate(at(400, sex: null))
          .results
          .values
          .every((x) => x.reason == 'missing_sex'),
      isTrue,
    );
    expect(
      engine
          .evaluate(at(400, oedema: Oedema.yes))
          .results[Index.weightAge]!
          .status,
      ResultStatus.unavailableOedema,
    );
    expect(
      engine
          .evaluate(at(400, oedema: Oedema.unknown))
          .results[Index.weightHeight]!
          .reason,
      'unknown_oedema',
    );
    final c = engine.evaluate(at(100, cm: 60, pos: Position.standing));
    expect(c.results[Index.heightAge]!.status, ResultStatus.needsReview);
    expect(c.results[Index.heightAge]!.rawZ, isNull);
    expect(c.correctedCm, isNull); // deliberate product divergence from R c9mo
    expect(c.results[Index.weightAge]!.rawZ, isNotNull);
  });
  test('finite positive validation per index', () {
    for (final bad in [
      0.0,
      -1.0,
      double.nan,
      double.infinity,
      double.negativeInfinity,
    ]) {
      expect(
        engine.evaluate(at(400, kg: bad)).results[Index.weightAge]!.status,
        ResultStatus.invalidInput,
      );
      expect(
        engine.evaluate(at(400, cm: bad)).results[Index.heightAge]!.status,
        ResultStatus.invalidInput,
      );
      expect(
        engine.evaluate(at(400, kg: bad)).results[Index.heightAge]!.rawZ,
        isNotNull,
      );
    }
  });
  test('length domains exact endpoints and epsilon no clamp', () {
    for (final spec in [
      (400, 45.0, 110.0, Position.recumbent),
      (900, 65.0, 120.0, Position.standing),
    ]) {
      for (final cm in [spec.$2, spec.$3]) {
        expect(
          engine
              .evaluate(at(spec.$1, cm: cm, pos: spec.$4))
              .results[Index.weightHeight]!
              .rawZ,
          isNotNull,
        );
      }
      for (final cm in [spec.$2 - 1e-8, spec.$3 + 1e-8]) {
        expect(
          engine
              .evaluate(at(spec.$1, cm: cm, pos: spec.$4))
              .results[Index.weightHeight]!
              .reason,
          'length_domain',
        );
      }
    }
  });
  test('LMS L0 defensive limit and weight tails, height unadjusted', () {
    expect(GrowthEngine.zscore(10, const Lms(0, 10, .1), adjusted: false), 0);
    const t = Lms(1, 10, .1);
    expect(GrowthEngine.zscore(14, t, adjusted: true), closeTo(4, 1e-12));
    expect(GrowthEngine.zscore(6, t, adjusted: true), closeTo(-4, 1e-12));
    expect(GrowthEngine.zscore(12, t, adjusted: false), closeTo(2, 1e-12));
  });
  test('R nearest-even rounding, categories and separate review pipelines', () {
    for (final x in [
      (1.125, 1.12),
      (1.375, 1.38),
      (-1.125, -1.12),
      (-1.375, -1.38),
    ]) {
      expect(GrowthEngine.roundOfficial(x.$1), x.$2);
    }
    final boundary = ScoreResult.scored(Index.weightAge, -2.004);
    expect(boundary.boundarySensitive, isTrue);
    expect(boundary.categoryFinal, 'berat badan kurang');
    expect(boundary.displayZ, '-2.00');
    final flagged = ScoreResult.scored(Index.weightAge, -6.004);
    expect(flagged.officialFlag, isFalse);
    expect(flagged.rawReviewFlag, isTrue);
    expect(flagged.reviewRequired, isTrue);
    expect(flagged.categoryFinal, isNull);
  });
  test('all category cutpoints and plausibility equality/sides', () {
    for (final i in Index.values) {
      for (final cut in [-3.0, -2.0, 1.0, 2.0, 3.0]) {
        for (final z in [cut - 1e-8, cut, cut + 1e-8]) {
          expect(GrowthEngine.category(i, z), isNotEmpty);
        }
      }
      final lo = i == Index.weightAge
          ? -6.0
          : i == Index.heightAge
          ? -6.0
          : -5.0;
      final hi = i == Index.weightAge
          ? 5.0
          : i == Index.heightAge
          ? 6.0
          : 5.0;
      expect(GrowthEngine.flag(i, lo), isFalse);
      expect(GrowthEngine.flag(i, hi), isFalse);
      expect(GrowthEngine.flag(i, lo - 1e-8), isTrue);
      expect(GrowthEngine.flag(i, hi + 1e-8), isTrue);
    }
    expect(GrowthEngine.category(Index.weightHeight, 1), 'gizi baik');
    expect(GrowthEngine.category(Index.weightHeight, 2), 'berisiko gizi lebih');
    expect(GrowthEngine.category(Index.weightHeight, 3), 'gizi lebih');
    expect(GrowthEngine.category(Index.heightAge, 3), 'normal');
    expect(GrowthEngine.category(Index.weightAge, -3), 'berat badan kurang');
  });
  test('version provenance follows result', () {
    final r = engine.evaluate(at(400));
    expect(
      r.provenance['whoCommit'],
      'b776d8a12b1c97369c748b561159fd2ec4f4db58',
    );
    expect(r.provenance['classificationPolicy'], 'permenkes-raw-v1');
    expect(r.provenance['tableManifestHash'], isNotEmpty);
  });
  test('max civil year stays valid without constructing year10004', () {
    final r = engine.evaluate(
      Measurement(
        birth: CivilDate(9999, 1, 1),
        measured: CivilDate(9999, 2, 1),
        sex: Sex.male,
        weightKg: 4,
        oedema: Oedema.no,
      ),
    );
    expect(r.results[Index.weightAge]!.rawZ, isNotNull);
  });
  test('SHA256 known vectors and pinned table corruption rejected', () {
    expect(
      sha256([]),
      'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
    );
    expect(
      sha256(utf8.encode('abc')),
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
    final tables = File('assets/engine/tables.json').readAsStringSync();
    final manifest = File('assets/engine/manifest.json').readAsStringSync();
    expect(
      () => GrowthEngine.fromJson('$tables ', manifest),
      throwsFormatException,
    );
    expect(
      () => GrowthEngine.fromJson(
        tables,
        manifest.replaceFirst('0.1.0', '0.2.0'),
      ),
      throwsFormatException,
    );
  });
  test('LMS interpolation and nonlinear weight tail branches independent equations', () {
    final tables = jsonDecode(
      File('assets/engine/tables.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final rows = tables['wfl'] as List;
    final a = rows.firstWhere((r) => r[0] == 1 && r[1] == 85.0) as List;
    final b = rows.firstWhere((r) => r[0] == 1 && r[1] == 85.1) as List;
    final fraction = (85.05 - 85.0) / .1;
    final t = Lms(
      (a[2] as num).toDouble() + fraction * ((b[2] as num) - (a[2] as num)),
      (a[3] as num).toDouble() + fraction * ((b[3] as num) - (a[3] as num)),
      (a[4] as num).toDouble() + fraction * ((b[4] as num) - (a[4] as num)),
    );
    expect(
      engine.evaluate(at(400, cm: 85.05)).results[Index.weightHeight]!.rawZ,
      closeTo(GrowthEngine.zscore(10, t, adjusted: true), 1e-12),
    );
    const nonlinear = Lms(-1, 10, .1);
    // q(z)=10/(1-.1*z); expected piecewise linear tail, not raw LMS.
    const upper3 = 10 / .7,
        upper2 = 10 / .8,
        lower3 = 10 / 1.3,
        lower2 = 10 / 1.2;
    expect(
      GrowthEngine.zscore(20, nonlinear, adjusted: true),
      closeTo(3 + (20 - upper3) / (upper3 - upper2), 1e-12),
    );
    expect(
      GrowthEngine.zscore(5, nonlinear, adjusted: true),
      closeTo(-3 + (5 - lower3) / (lower2 - lower3), 1e-12),
    );
    expect(
      GrowthEngine.zscore(20, nonlinear, adjusted: false),
      closeTo(5, 1e-12),
    );
  });
  test('category inequalities all meaningful cuts at equality and sides', () {
    final cases = <Index, List<(double, String, String, String)>>{
      Index.weightAge: [
        (
          -3,
          'berat badan sangat kurang',
          'berat badan kurang',
          'berat badan kurang',
        ),
        (-2, 'berat badan kurang', 'berat badan normal', 'berat badan normal'),
        (
          1,
          'berat badan normal',
          'berat badan normal',
          'risiko berat badan lebih',
        ),
      ],
      Index.heightAge: [
        (-3, 'sangat pendek', 'pendek', 'pendek'),
        (-2, 'pendek', 'normal', 'normal'),
        (3, 'normal', 'normal', 'tinggi'),
      ],
      Index.weightHeight: [
        (-3, 'gizi buruk', 'gizi kurang', 'gizi kurang'),
        (-2, 'gizi kurang', 'gizi baik', 'gizi baik'),
        (1, 'gizi baik', 'gizi baik', 'berisiko gizi lebih'),
        (2, 'berisiko gizi lebih', 'berisiko gizi lebih', 'gizi lebih'),
        (3, 'gizi lebih', 'gizi lebih', 'obesitas'),
      ],
    };
    for (final i in cases.keys) {
      for (final c in cases[i]!) {
        expect(GrowthEngine.category(i, c.$1 - 1e-8), c.$2);
        expect(GrowthEngine.category(i, c.$1), c.$3);
        expect(GrowthEngine.category(i, c.$1 + 1e-8), c.$4);
      }
    }
    expect(
      () => GrowthEngine.category(Index.weightAge, double.nan),
      throwsArgumentError,
    );
    for (final i in Index.values) {
      final lo = i == Index.weightHeight ? -5.0 : -6.0;
      final hi = i == Index.heightAge ? 6.0 : 5.0;
      expect(GrowthEngine.flag(i, lo + 1e-8), isFalse);
      expect(GrowthEngine.flag(i, hi - 1e-8), isFalse);
    }
  });
  test('day0 table support, corrected domain and safety conditions', () {
    expect(
      engine
          .evaluate(at(0, kg: 3, cm: 50))
          .results
          .values
          .every((x) => x.rawZ != null),
      isTrue,
    );
    expect(
      engine.evaluate(at(731, cm: 65)).results[Index.weightHeight]!.reason,
      'length_domain',
    );
    final accepted = engine.evaluate(at(731, cm: 65, pos: Position.standing));
    expect(accepted.results[Index.weightHeight]!.rawZ, isNotNull);
    final birthday = engine.evaluate(
      Measurement(
        birth: CivilDate(2021, 3, 1),
        measured: CivilDate(2026, 3, 1),
        sex: Sex.female,
      ),
    );
    expect(birthday.ageDays, 1826);
    expect(birthday.results[Index.weightAge]!.reason, 'fifth_birthday');
    final oedema = engine.evaluate(at(400, oedema: Oedema.yes));
    expect(oedema.results[Index.heightAge]!.rawZ, isNotNull);
    final unknown = engine.evaluate(at(400, oedema: Oedema.unknown));
    expect(unknown.results[Index.heightAge]!.rawZ, isNotNull);
    expect(unknown.results[Index.weightAge]!.rawZ, isNull);
  });
  test('existing rounded and instrumented raw oracle: actual Dart comparisons', () {
    const base = 'test/fixtures/oracle/';
    List<Map<String, String>> csv(String file) {
      final lines = File(file).readAsLinesSync();
      final header = lines.first.replaceAll('"', '').split(',');
      return lines.skip(1).where((x) => x.isNotEmpty).map((line) {
        final vals = line.replaceAll('"', '').split(',');
        return Map.fromIterables(header, vals);
      }).toList();
    }

    final inputs = csv('${base}sas-survey_z_st.csv');
    final rounded = csv('${base}official-wrapper.csv');
    final raw = csv('${base}instrumented-wrapper.csv');
    double? number(String? s) => double.tryParse(s ?? '');
    final counts = {
      for (final i in Index.values)
        i: {
          'numeric': 0,
          'bothMissing': 0,
          'policyDivergence': 0,
          'maxRawDiff': 0.0,
          'roundedMatches': 0,
          'flagMatches': 0,
        },
    };
    final differences = <Map<String, dynamic>>[];
    for (var n = 0; n < inputs.length; n++) {
      final row = inputs[n];
      expect(row['id'], rounded[n]['id']);
      expect(row['id'], raw[n]['id']);
      final days = (double.parse(row['agemons']!) * 30.4375 + .5).floor();
      final dob = CivilDate(2020, 1, 1);
      final r = engine.evaluate(
        Measurement(
          birth: dob,
          measured: dob.addDays(days),
          sex: row['GENDER'] == '1' ? Sex.male : Sex.female,
          weightKg: number(row['WEIGHT']),
          rawCm: number(row['HEIGHT']),
          rawPosition: row['measure']!.toLowerCase() == 'l'
              ? Position.recumbent
              : row['measure']!.toLowerCase() == 'h'
              ? Position.standing
              : null,
          oedema: row['oedema'] == 'y' ? Oedema.yes : Oedema.no,
        ),
      );
      for (final i in Index.values) {
        final col = {
          Index.weightAge: 'wei',
          Index.heightAge: 'len',
          Index.weightHeight: 'wfl',
        }[i]!;
        final expected = number(raw[n]['z$col']);
        final actual = r.results[i]!;
        final c = counts[i]!;
        if (expected != null && actual.rawZ != null) {
          final diff = (expected - actual.rawZ!).abs();
          c['numeric'] = (c['numeric'] as int) + 1;
          if (diff > (c['maxRawDiff'] as double)) c['maxRawDiff'] = diff;
          expect(diff, lessThanOrEqualTo(1e-10), reason: 'id ${row['id']} $i');
          expect(actual.officialRoundedZ, number(rounded[n]['z$col']));
          c['roundedMatches'] = (c['roundedMatches'] as int) + 1;
          expect(actual.officialFlag, rounded[n]['f$col'] == '1');
          c['flagMatches'] = (c['flagMatches'] as int) + 1;
          if (i == Index.heightAge) {
            expect(
              r.correctedCm,
              closeTo(number(rounded[n]['clenhei'])!, 1e-10),
            );
          }
        } else if (expected == null && actual.rawZ == null) {
          c['bothMissing'] = (c['bothMissing'] as int) + 1;
        } else {
          c['policyDivergence'] = (c['policyDivergence'] as int) + 1;
          differences.add({
            'id': row['id'],
            'index': i.name,
            'reason': actual.reason,
            'expected': expected,
            'actual': actual.rawZ,
          });
        }
      }
    }
    expect(
      differences,
      isEmpty,
      reason: 'shared cohort must explicitly account for any safe policy divergence',
    );
    expect(counts[Index.weightAge]!['numeric'], 485);
    expect(counts[Index.heightAge]!['numeric'], 471);
    expect(counts[Index.weightHeight]!['numeric'], 463);
  });
}
