import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sigibas_rasp/mvp/nutrition.dart';
import 'package:sigibas_rasp/mvp/kms.dart';

void main() {
  test('indikasi overweight memerlukan pemeriksaan sebelum target PMT', () {
    expect(
      PmtAdvice.assess(months: 24, wfhZ: 2.1, growthConcern: true).kind,
      PmtKind.assessment,
    );
    expect(PmtAdvice.assess(months: 24, wfhZ: 2.1, wfaZ: -2.5).range, isNull);
  });
  test(
    'seluruh nilai AKG sesuai Lampiran I Permenkes 28/2019 pada batas usia',
    () {
      const rows = {
        0: [550, 9, 31, 59, 0, 700, 0.3, 375, 10],
        5: [550, 9, 31, 59, 0, 700, 0.3, 375, 10],
        6: [800, 15, 35, 105, 11, 900, 11, 400, 10],
        11: [800, 15, 35, 105, 11, 900, 11, 400, 10],
        12: [1350, 20, 45, 215, 19, 1150, 7, 400, 15],
        47: [1350, 20, 45, 215, 19, 1150, 7, 400, 15],
        48: [1400, 25, 50, 220, 20, 1450, 10, 450, 15],
        83: [1400, 25, 50, 220, 20, 1450, 10, 450, 15],
      };
      for (final row in rows.entries) {
        final a = AkgReference.forMonths(row.key)!;
        expect([
          a.energy,
          a.protein,
          a.fat,
          a.carbohydrate,
          a.fiber,
          a.water,
          a.ironMg,
          a.vitaminARe,
          a.vitaminDMcg,
        ], row.value);
        expect(a.percentEnergy(a.energy * .75), closeTo(75, 1e-9));
        expect(a.percentProtein(a.protein * .5), closeTo(50, 1e-9));
      }
    },
  );
  test('PMT batas LiLA, kelompok umur, protein, dan prioritas rujukan', () {
    for (final month in [6, 8, 9, 11, 12, 23, 24, 59]) {
      final advice = PmtAdvice.assess(months: month, wfhZ: -2.5);
      final expected = month < 12
          ? [175, 200, 3.5, 8]
          : month < 24
          ? [225, 275, 4.5, 11]
          : [300, 450, 6, 18];
      expect(advice.kind, PmtKind.candidate);
      expect([
        advice.range!.energyMin,
        advice.range!.energyMax,
        advice.range!.proteinMin,
        advice.range!.proteinMax,
      ], expected);
    }
    expect(PmtAdvice.assess(months: 12, muac: 11.5).kind, PmtKind.candidate);
    expect(PmtAdvice.assess(months: 12, muac: 12.5).kind, PmtKind.education);
    expect(PmtAdvice.assess(months: 12, wfhZ: -3.001).kind, PmtKind.referral);
    expect(
      PmtAdvice.assess(months: 12, wfhZ: -2.5, allergies: true).kind,
      PmtKind.assessment,
    );
    expect(
      PmtAdvice.assess(months: 12, wfhZ: -2.5, redFlags: true).kind,
      PmtKind.referral,
    );
  });
  test('official iron, vitamin A and D by complete age group with units', () {
    for (final entry in {
      0: [0.3, 375, 10],
      5: [0.3, 375, 10],
      6: [11, 400, 10],
      11: [11, 400, 10],
      12: [7, 400, 15],
      47: [7, 400, 15],
      48: [10, 450, 15],
      83: [10, 450, 15],
    }.entries) {
      final ref = AkgReference.forMonths(entry.key)!;
      expect([ref.ironMg, ref.vitaminARe, ref.vitaminDMcg], entry.value);
    }
    expect(AkgReference.forMonths(12)!.percentIron(3.5), 50);
    expect(AkgReference.forMonths(12)!.percentVitaminA(200), 50);
    expect(AkgReference.forMonths(12)!.percentVitaminD(7.5), 50);
    expect(
      () => AkgReference.forMonths(12)!.percentIron(-1),
      throwsArgumentError,
    );
    expect(
      () => AkgReference.forMonths(12)!.percentVitaminA(double.infinity),
      throwsArgumentError,
    );
  });
  test('AKG exact completed-month boundaries and invalid ages', () {
    expect(AkgReference.forMonths(-1), isNull);
    expect(AkgReference.forMonths(5)!.energy, 550);
    expect(AkgReference.forMonths(6)!.protein, 15);
    expect(AkgReference.forMonths(11)!.energy, 800);
    expect(AkgReference.forMonths(12)!.energy, 1350);
    expect(AkgReference.forMonths(47)!.protein, 20);
    expect(AkgReference.forMonths(48)!.energy, 1400);
    expect(AkgReference.forMonths(83)!.protein, 25);
    expect(AkgReference.forMonths(84), isNull);
    expect(AkgReference.forMonths(12)!.percentEnergy(675), 50);
    expect(
      () => AkgReference.forMonths(12)!.percentEnergy(double.nan),
      throwsArgumentError,
    );
  });
  test('PMT safety takes priority; no prescription without assessment', () {
    expect(PmtAdvice.assess(months: 5).kind, PmtKind.outsideAge);
    expect(PmtAdvice.assess(months: 60).kind, PmtKind.outsideAge);
    expect(PmtAdvice.assess(months: 12).kind, PmtKind.assessment);
    expect(
      PmtAdvice.assess(months: 12, wfhZ: -3.01, wfaZ: -2.5).kind,
      PmtKind.referral,
    );
    expect(PmtAdvice.assess(months: 12, muac: 11.49).kind, PmtKind.referral);
    expect(PmtAdvice.assess(months: 12, oedema: true).range, isNull);
    expect(PmtAdvice.assess(months: 12, allergies: true).range, isNull);
    expect(
      PmtAdvice.assess(months: 6, wfhZ: -3, wfaZ: -2.5).range!.energyMin,
      175,
    );
    expect(PmtAdvice.assess(months: 11, wfhZ: -2.5).range!.energyMax, 200);
    expect(PmtAdvice.assess(months: 12, wfhZ: -2.5).range!.energyMax, 275);
    expect(PmtAdvice.assess(months: 24, wfhZ: -2.5).range!.energyMax, 450);
    expect(PmtAdvice.assess(months: 59, wfaZ: -2).kind, PmtKind.education);
    expect(
      PmtAdvice.assess(months: 12, wfhZ: double.nan).kind,
      PmtKind.assessment,
    );
  });
  test('WHO verified curves have correct sex medians and ordered z bands', () {
    final ref = GrowthCurves.fromJson(
      File('assets/engine/tables.json').readAsStringSync(),
      File('assets/engine/manifest.json').readAsStringSync(),
    );
    expect(ref.weightAt('male', 0, 0), closeTo(3.3464, 0.00001));
    expect(ref.weightAt('female', 0, 0), closeTo(3.2322, 0.00001));
    expect(
      ref.weightAt('male', 0, -3)!,
      lessThan(ref.weightAt('male', 0, -2)!),
    );
    expect(ref.weightAt('unknown', 0, 0), isNull);
    expect(ref.weightAt('male', 1827, 0), isNull);
    expect(() => GrowthCurves.fromJson('{}', '{}'), throwsFormatException);
  });
  test('chart excludes pending, invalid and out-of-range records', () {
    final records = [
      {
        'status': 'approved',
        'input': {'date': '2026-02-01', 'weight': 5},
      },
      {
        'status': 'pending',
        'input': {'date': '2026-03-01', 'weight': 6},
      },
      {
        'status': 'approved',
        'input': {'date': '2025-12-31', 'weight': 4},
      },
      {
        'status': 'approved',
        'input': {'date': 'bad', 'weight': 7},
      },
      {
        'status': 'approved',
        'input': {'date': '2026-04-01', 'weight': double.nan},
      },
    ];
    final points = GrowthPoint.approved({'birth': '2026-01-01'}, records);
    expect(points.length, 1);
    expect(points.single.days, 31);
    expect(points.single.kg, 5);
    expect(GrowthPoint.approved({}, records), isEmpty);
  });
}
