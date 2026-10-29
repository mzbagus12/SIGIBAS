import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'engine/engine.dart';
import 'mvp/repository.dart';
import 'mvp/storage.dart';
import 'mvp/demo_session.dart';
import 'mvp/local_security.dart';

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
    final repository = await MvpRepository.open(
      await openMvpDatabase(),
      engine,
    );
    await repository.initializeDummyProfiles();
    return repository;
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
      return DemoSession(repo: snapshot.data!);
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
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF087B6C),
        primary: const Color(0xFF096B5D),
        secondary: const Color(0xFFBC7042),
        surface: Colors.white,
      ),
      scaffoldBackgroundColor: const Color(0xFFF2F6F3),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFFF2F6F3),
        foregroundColor: Color(0xFF123D36),
        elevation: 0,
        titleTextStyle: TextStyle(
          color: Color(0xFF123D36),
          fontSize: 18,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFFE0EBE5)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF8FAF8),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFD6E4DC)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    ),
    home: const LocalSecurityGate(child: Bootstrap()),
  );
}
