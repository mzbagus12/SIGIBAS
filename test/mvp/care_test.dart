import 'dart:ui' as ui;
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_io.dart';
import 'package:sigibas_rasp/engine/engine.dart';
import 'package:sigibas_rasp/mvp/repository.dart';

void main() {
  late MvpRepository repo;
  setUp(() async {
    final dir = await Directory('.dart_tool').createTemp('care-');
    repo = await MvpRepository.open(
      await databaseFactoryIo.openDatabase('${dir.path}/data.db'),
      GrowthEngine.fromJson(
        File('assets/engine/tables.json').readAsStringSync(),
        File('assets/engine/manifest.json').readAsStringSync(),
      ),
      today: '2026-10-29',
    );
  });
  tearDown(() => repo.close());
  test('foto disimpan, bertahan setelah buka ulang, dihapus, dan batas ukuran ditolak', () async {
    final id = await repo.register(
      'photo-child',
      'Dummy',
      '2024-01-01',
      'male',
    );
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawColor(const ui.Color(0xFF087B6C), ui.BlendMode.src);
    final picture = recorder.endRecording();
    final raster = await picture.toImage(2, 2);
    final data = (await raster.toByteData(format: ui.ImageByteFormat.png))!;
    final image = data.buffer.asUint8List();
    raster.dispose();
    picture.dispose();
    await repo.updatePhoto('photo-save', id, image);
    expect(repo.state['children'][id]['photo'], isA<String>());
    final path = repo.db.path;
    final engine = repo.engine;
    await repo.close();
    repo = await MvpRepository.open(
      await databaseFactoryIo.openDatabase(path),
      engine,
      today: '2026-10-29',
    );
    expect(
      base64Decode(repo.state['children'][id]['photo']).length,
      greaterThan(0),
    );
    await expectLater(
      repo.updatePhoto('photo-big', id, Uint8List(262145)),
      throwsFormatException,
    );
    await repo.updatePhoto('photo-remove', id, null);
    expect(repo.state['children'][id]['photo'], isNull);
    await repo.archiveChild('photo-archive', id);
    await expectLater(
      repo.updatePhoto('photo-archived', id, null),
      throwsStateError,
    );
  });
  test('foto terlalu lebar ditolak tanpa mengganti foto tersimpan', () async {
    final id = await repo.register(
      'photo-limit',
      'Dummy',
      '2024-01-01',
      'male',
    );
    Future<Uint8List> png(int width, int height) async {
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder)
          .drawColor(const ui.Color(0xFF087B6C), ui.BlendMode.src);
      final picture = recorder.endRecording();
      final image = await picture.toImage(width, height);
      try {
        return (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
            .asUint8List();
      } finally {
        image.dispose();
        picture.dispose();
      }
    }

    await repo.updatePhoto('photo-valid', id, await png(300, 150));
    final stored = repo.state['children'][id]['photo'] as String;
    final codec = await ui.instantiateImageCodec(base64Decode(stored));
    final frame = await codec.getNextFrame();
    expect(frame.image.width, 256);
    expect(frame.image.height, 128);
    frame.image.dispose();
    codec.dispose();
    await expectLater(
      repo.updatePhoto('photo-too-wide', id, await png(2049, 1)),
      throwsFormatException,
    );
    expect(repo.state['children'][id]['photo'], stored);
  });
  test(
    'inisialisasi dummy tidak menggandakan atau mengganti profil lama',
    () async {
      await repo.initializeDummyProfiles();
      expect((repo.state['children'] as Map).length, 2);
      await repo.updateProfile('rename', 'demo-local-1', {
        'name': 'Nama diubah',
      });
      await repo.initializeDummyProfiles();
      expect((repo.state['children'] as Map).length, 2);
      expect(repo.state['children']['demo-local-1']['name'], 'Nama diubah');
    },
  );
  test('NIK dummy hanya menerima 16 angka dengan awalan 000000', () async {
    final id = await repo.register('nik-child', 'Dummy', '2024-01-01', 'male');
    await expectLater(
      repo.updateProfile('nik-bad', id, {'nik': '123'}),
      throwsFormatException,
    );
    await expectLater(
      repo.updateProfile('nik-real', id, {'nik': '1234567890123456'}),
      throwsFormatException,
    );
    await repo.updateProfile('nik-ok', id, {'nik': '0000001234567890'});
    expect(repo.state['children'][id]['nik'], '0000001234567890');
  });
  test(
    'pertukaran dua arah menerapkan data remote dan menyimpan versi',
    () async {
      final c = await repo.register('child', 'Sintetis', '2024-01-01', 'male');
      final result = await repo.exchangeState('kader', (changes) async {
        expect(changes.single['kind'], 'child');
        return {
          'ack': [changes.single['operation']],
          'records': [
            {
              'kind': 'child',
              'id': c,
              'version': 1,
              'value': changes.single['value'],
            },
            {
              'kind': 'visit',
              'id': c,
              'version': 1,
              'value': {'date': '2026-11-02', 'note': 'Dari server'},
            },
          ],
        };
      });
      expect(result, 2);
      expect(repo.state['visits'][c]['note'], 'Dari server');
      await repo.exchangeState('kader', (changes) async {
        expect(changes, isEmpty);
        return {'ack': [], 'records': []};
      });
    },
  );
  test(
    'profil dapat diperbarui dan diarsipkan tanpa menghapus revisi',
    () async {
      final c = await repo.register('child', 'Sintetis', '2024-01-01', 'male');
      await repo.updateProfile('profile', c, {
        'name': 'Baru',
        'guardian': 'Wali demo',
        'village': 'Wilayah A',
        'exclusiveBreastfeeding': 'unknown',
        'immunization': 'unknown',
      });
      expect(repo.state['children'][c]['village'], 'Wilayah A');
      final r = await repo.save('before-archive', c, {
        'date': '2026-10-01',
        'weight': 12,
        'cm': 88,
        'position': 'standing',
        'oedema': 'no',
      });
      final snapshot = repo.state['revisions'][r];
      await expectLater(
        repo.updateProfile('invalid', c, {'name': ''}),
        throwsFormatException,
      );
      await repo.archiveChild('archive', c);
      expect(repo.state['children'][c]['archived'], true);
      expect(repo.state['revisions'][r], snapshot);
      await expectLater(
        repo.save('draft', c, {'date': '2026-10-01'}),
        throwsStateError,
      );
    },
  );
  test('profil arsip dipulihkan tanpa mengubah riwayat dan dikirim saat sinkronisasi', () async {
    final child = await repo.register(
      'restore-child',
      'Dummy',
      '2024-01-01',
      'male',
    );
    final revision = await repo.save('restore-draft', child, {
      'date': '2026-10-01',
      'weight': 12,
      'cm': 88,
      'position': 'standing',
      'oedema': 'no',
    });
    await repo.exchangeState(
      'kader',
      (changes) async => {
        'ack': changes.map((c) => c['operation']).toList(),
        'records': changes
            .map(
              (c) => {
                'kind': c['kind'],
                'id': c['id'],
                'version': 1,
                'value': c['value'],
              },
            )
            .toList(),
      },
    );
    await repo.archiveChild('restore-archive', child);
    await repo.exchangeState(
      'kader',
      (changes) async => {
        'ack': changes.map((c) => c['operation']).toList(),
        'records': changes
            .map(
              (c) => {
                'kind': c['kind'],
                'id': c['id'],
                'version': 2,
                'value': c['value'],
              },
            )
            .toList(),
      },
    );
    final before = repo.state['revisions'][revision];
    await repo.restoreChild('restore-profile', child);
    expect(repo.state['children'][child]['archived'], false);
    expect(repo.state['revisions'][revision], before);
    await repo.updateProfile('restore-update', child, {'name': 'Dummy pulih'});
    await repo.exchangeState('kader', (changes) async {
      expect(
        changes.where((c) => c['kind'] == 'child').single['value']['archived'],
        false,
      );
      return {
        'ack': changes.map((c) => c['operation']).toList(),
        'records': changes
            .map(
              (c) => {
                'kind': c['kind'],
                'id': c['id'],
                'version': 3,
                'value': c['value'],
              },
            )
            .toList(),
      };
    });
    await expectLater(repo.restoreChild('missing', 'absent'), throwsStateError);
    await expectLater(repo.restoreChild('active', child), throwsStateError);
  });
  test(
    'KMS memakai persetujuan efektif dan jadwal bertahan setelah dibuka ulang',
    () async {
      final c = await repo.register('child', 'Sintetis', '2024-01-01', 'male');
      final r = await repo.save('first', c, {
        'date': '2026-10-01',
        'weight': 12,
        'cm': 88,
        'position': 'standing',
        'oedema': 'no',
        'muac': 14,
        'head': 48,
      });
      expect(repo.growthHistory(c), isEmpty);
      await repo.submit('submit', r);
      await repo.review('approve', r, true, '');
      expect(repo.growthHistory(c).single['input']['muac'], 14);
      final correction = await repo.save('correct', c, {
        'date': '2026-10-01',
        'weight': 12.2,
        'cm': 88,
        'position': 'standing',
        'oedema': 'no',
      }, previous: r);
      expect(repo.growthHistory(c).single['id'], r);
      await repo.submit('submit-new', correction);
      await repo.review('approve-new', correction, true, '');
      expect(repo.growthHistory(c).single['id'], correction);
      await repo.scheduleVisit('visit', c, '2026-11-01', 'Penimbangan ulang');
      expect(repo.state['visits'][c]['date'], '2026-11-01');
      final dbPath = repo.db.path;
      final engine = repo.engine;
      await repo.close();
      repo = await MvpRepository.open(
        await databaseFactoryIo.openDatabase(dbPath),
        engine,
        today: '2026-10-29',
      );
      expect(repo.state['visits'][c]['date'], '2026-11-01');
      expect(repo.growthHistory(c).single['id'], correction);
      await expectLater(
        repo.scheduleVisit('past', c, '2026-01-01', ''),
        throwsFormatException,
      );
      await expectLater(
        repo.save('bad', c, {'date': '2026-10-01', 'muac': -2}),
        throwsFormatException,
      );
    },
  );
}
