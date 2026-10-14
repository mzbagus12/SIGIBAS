import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'engine/engine.dart';
import 'mvp/repository.dart';
import 'mvp/storage.dart';
import 'mvp/ui.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class Bootstrap extends StatefulWidget {
  const Bootstrap({super.key});
  @override
  State<Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<Bootstrap> {
  late final Future<MvpRepository> repo = _open();
  Future<MvpRepository> _open() async {
    final engine = GrowthEngine.fromJson(
      await rootBundle.loadString('assets/engine/tables.json'),
      await rootBundle.loadString('assets/engine/manifest.json'),
    );
    return MvpRepository.open(await openMvpDatabase(), engine);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<MvpRepository>(
    future: repo,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Scaffold(
          appBar: AppBar(title: const Text('SI-GIBAS RASP')),
          body: Text(
            'Gagal membuka data/engine; database dipertahankan, tanpa reset. ${snapshot.error}',
          ),
        );
      }
      if (!snapshot.hasData) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      return MvpWorkspace(repo: snapshot.data!);
    },
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'SI-GIBAS RASP',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF00695C)),
      useMaterial3: true,
    ),
    home: const Bootstrap(),
  );
}
