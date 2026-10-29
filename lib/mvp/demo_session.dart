import 'package:flutter/material.dart';

import 'repository.dart';
import 'ui.dart';
import 'local_accounts.dart';

/// Alur login demonstrasi lokal; kredensial ini tidak memberi keamanan data.
class DemoSession extends StatefulWidget {
  final MvpRepository repo;
  const DemoSession({super.key, required this.repo});
  @override
  State<DemoSession> createState() => _DemoSessionState();
}

class _DemoSessionState extends State<DemoSession> with WidgetsBindingObserver {
  late final accounts = LocalAccounts(widget.repo.db);
  bool? ready;
  bool busy = false;
  int sessionGeneration = 0;
  final setupPins = {
    for (final id in LocalAccounts.roles.keys) id: TextEditingController(),
  };
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    accounts.configured().then((value) {
      if (mounted) setState(() => ready = value);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      logout();
    }
  }

  final user = TextEditingController();
  final pin = TextEditingController();
  String? role;
  String? error;
  bool showPin = false;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final controller in setupPins.values) {
      controller.dispose();
    }
    user.dispose();
    pin.dispose();
    super.dispose();
  }

  Future<void> login() async {
    if (busy) return;
    final generation = sessionGeneration;
    setState(() => busy = true);
    try {
      final result = await accounts.login(
        user.text.trim().toLowerCase(),
        pin.text,
      );
      if (!mounted || generation != sessionGeneration) return;
      pin.clear();
      setState(() {
        role = result;
        error = result == null ? 'ID atau PIN tidak sesuai.' : null;
      });
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is StateError
              ? e.message.toString()
              : 'Login gagal. Coba lagi.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> setup() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await accounts.configure(setupPins.map((id, c) => MapEntry(id, c.text)));
      for (final c in setupPins.values) {
        c.clear();
      }
      if (mounted) {
        setState(() {
          ready = true;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is FormatException
              ? e.message
              : 'Akun tidak dapat disiapkan.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void logout() {
    sessionGeneration++;
    user.clear();
    pin.clear();
    setState(() {
      role = null;
      error = null;
      showPin = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (ready == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (ready == false) {
      return Scaffold(
        appBar: AppBar(title: const Text('Siapkan akun lokal')),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              'Tetapkan PIN berbeda untuk Kader, Badan Gizi, dan Pemerintah. Gunakan 6–12 angka dan simpan PIN Anda.',
            ),
            for (final id in LocalAccounts.roles.keys)
              TextField(
                key: ValueKey('setup-$id'),
                controller: setupPins[id],
                obscureText: true,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'PIN ${LocalAccounts.roles[id]}',
                ),
              ),
            if (error != null) Text(error!),
            FilledButton(
              onPressed: busy ? null : setup,
              child: const Text('Simpan akun'),
            ),
          ],
        ),
      );
    }
    if (role != null) {
      return MvpWorkspace(
        key: ValueKey(role),
        repo: widget.repo,
        role: role!,
        onLogout: logout,
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('SI-GIBAS')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF0B5049), Color(0xFF168874)],
                    ),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.favorite_rounded, color: Colors.white),
                      SizedBox(height: 18),
                      Text(
                        'Masuk ke SI-GIBAS',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 25,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Masuk dengan akun lokal sesuai peran.',
                        style: TextStyle(color: Color(0xFFE0F3EC)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Gunakan PIN yang Anda tetapkan saat persiapan akun. Data latihan tersimpan pada perangkat ini.',
                  style: TextStyle(color: Color(0xFF704721)),
                ),
                const SizedBox(height: 16),
                TextField(
                  key: const Key('login-user'),
                  controller: user,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'ID akun'),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('login-pin'),
                  controller: pin,
                  obscureText: !showPin,
                  keyboardType: TextInputType.number,
                  onSubmitted: (_) => login(),
                  decoration: InputDecoration(
                    labelText: 'PIN',
                    suffixIcon: IconButton(
                      tooltip: showPin ? 'Sembunyikan PIN' : 'Tampilkan PIN',
                      onPressed: () => setState(() => showPin = !showPin),
                      icon: Icon(
                        showPin
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                    ),
                  ),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: busy ? null : login,
                  child: const Text('Masuk'),
                ),
                const SizedBox(height: 18),
                const Text(
                  'ID akun berdasarkan peran',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Kader: kader\nBadan Gizi: gizi\nPemerintah: pemerintah',
                  style: TextStyle(height: 1.6),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
