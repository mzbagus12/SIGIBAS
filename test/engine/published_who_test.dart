import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sigibas_rasp/engine/engine.dart';

void main() {
  final engine = GrowthEngine.fromJson(
    File('assets/engine/tables.json').readAsStringSync(),
    File('assets/engine/manifest.json').readAsStringSync(),
  );
  final cases = jsonDecode(
    File('test/fixtures/who_published_lms_cases.json').readAsStringSync(),
  ) as List;
  for (var n = 0; n < cases.length; n++) {
    final c = cases[n] as Map;
    test(
      'WHO published LMS independent case $n ${c['index']} ${c['sex']} day${c['days']} z${c['z']}',
      () {
        final birth = CivilDate(2024, 1, 1);
        final result = engine.evaluate(
          Measurement(
            birth: birth,
            measured: birth.addDays(c['days']),
            sex: c['sex'] == 'male' ? Sex.male : Sex.female,
            weightKg: (c['kg'] as num).toDouble(),
            rawCm: (c['cm'] as num).toDouble(),
            rawPosition: c['days'] <= 730
                ? Position.recumbent
                : Position.standing,
            oedema: Oedema.no,
          ),
        );
        final score = result
            .results[Index.values.firstWhere((i) => i.name == c['index'])]!;
        expect(score.rawZ, closeTo(c['z'], 0.00001));
        expect(score.categoryFinal, c['category']);
      },
    );
  }
}
