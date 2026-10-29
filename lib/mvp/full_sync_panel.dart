import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sembast/sembast.dart';

import 'demo_sync.dart';
import 'repository.dart';
import 'local_security.dart';
import 'sync_visit_reminders.dart';
import 'visit_notification.dart';

class FullSyncPanel extends StatefulWidget {
  final MvpRepository repo;
  final String role;
  final VoidCallback onChanged;
  const FullSyncPanel({
    super.key,
    required this.repo,
    required this.role,
    required this.onChanged,
  });
  @override
  State<FullSyncPanel> createState() => _FullSyncPanelState();
}

class _FullSyncPanelState extends State<FullSyncPanel>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  String? token;
  bool busy = false;
  String status = 'Belum tersambung';
  Timer? timer;
  final pin = TextEditingController();
  String get account => widget.role == 'Kader'
      ? 'kader'
      : widget.role == 'Pemerintah'
      ? 'pemerintah'
      : 'gizi';

  Future<bool> reconcileReminders() async {
    if (account == 'pemerintah') return true;
    final record = stringMapStoreFactory.store('notifications').record('sync');
    final saved = await record.get(widget.repo.db) ?? {};
    final ledger = saved.map((key, value) => MapEntry(key, value as String));
    final ok = await reconcileVisitReminders(
      widget.repo.state,
      ledger,
      (id, date) async {
        final message = await scheduleVisitNotification(
          id,
          date,
          requestPermission: false,
        );
        return !message.contains('izin notifikasi belum diberikan');
      },
      (id) async {
        await cancelVisitNotification(id);
        return true;
      },
      currentState: () => widget.repo.state,
    );
    await record.put(widget.repo.db, ledger);
    return ok;
  }

  @override
  void dispose() {
    timer?.cancel();
    pin.dispose();
    super.dispose();
  }

  Future<void> connect() async {
    setState(() => busy = true);
    try {
      final reply = await sendDemoRequest(account, '/sync-login', {
        'user': account,
        'pin': pin.text,
      });
      pin.clear();
      if (reply['token'] is! String || reply['role'] != account) {
        throw StateError('Sesi tidak sesuai');
      }
      token = reply['token'];
      timer?.cancel();
      timer = Timer.periodic(const Duration(seconds: 30), (_) {
        if (mounted && !busy) synchronize();
      });
      if (mounted) setState(() => status = 'Sesi lokal aktif');
    } catch (_) {
      if (mounted) {
        setState(
          () => status = 'Gagal tersambung. Periksa server dan PIN demo.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
    if (mounted && token != null) await synchronize();
  }

  Future<void> changePin() async {
    final old = TextEditingController(), replacement = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ganti PIN sinkronisasi server'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'PIN ini khusus sesi server lokal. Login tampilan demo tetap memakai PIN awal.',
            ),
            TextField(
              controller: old,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'PIN server lama'),
            ),
            TextField(
              controller: replacement,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'PIN server baru (minimal 8 karakter)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Ganti'),
          ),
        ],
      ),
    );
    if (accepted == true && mounted) {
      setState(() => busy = true);
      try {
        await sendDemoRequest(account, '/sync-password', {
          'token': token,
          'oldPin': old.text,
          'newPin': replacement.text,
        });
        timer?.cancel();
        token = null;
        if (mounted) {
          setState(
            () => status =
                'PIN server diganti. Semua sesi akun dicabut; hubungkan ulang.',
          );
        }
      } catch (_) {
        if (mounted) {
          setState(
            () => status =
                'PIN gagal diganti. Periksa PIN lama dan panjang PIN baru.',
          );
        }
      } finally {
        if (mounted) setState(() => busy = false);
      }
    }
    old.dispose();
    replacement.dispose();
  }

  Future<void> synchronize() async {
    if (busy || token == null) return;
    setState(() => busy = true);
    try {
      // Event retry is independent of record synchronization and remains local
      // when secure storage or the server cannot be reached.
      try {
        final events = await pendingSecurityEvents();
        if (events.isNotEmpty) {
          final batch = events.take(10).toList();
          final reply = await sendDemoRequest(account, '/security-events', {
            'token': token,
            'events': batch,
          });
          final ack = reply['ack'];
          if (ack is List &&
              ack.every(
                (id) => id is String && batch.any((e) => e['eventId'] == id),
              )) {
            await ackSecurityEvents(ack.cast<String>());
          }
        }
      } catch (_) {
        /* Retry with the next authenticated synchronization. */
      }
      final count = await widget.repo.exchangeState(
        account,
        (changes) => sendDemoRequest(account, '/sync', {
          'synthetic': true,
          'token': token,
          'changes': changes,
          'limit': 25,
        }),
        fetchPage: (cursor) => sendDemoRequest(account, '/sync', {
          'synthetic': true,
          'token': token,
          'changes': [],
          'limit': 25,
          'cursor': cursor,
        }),
      );
      var remindersOk = false;
      try {
        remindersOk = await reconcileReminders();
      } catch (_) {
        // The next sync retries reminder reconciliation.
      }
      if (mounted) {
        setState(
          () => status = remindersOk
              ? 'Tersinkron: $count record diterima.'
              : 'Tersinkron: $count record diterima. Periksa izin pengingat; akan dicoba lagi.',
        );
        widget.onChanged();
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => status = 'Belum tersinkron. Periksa koneksi/sesi atau konflik versi; data lokal dipertahankan.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return content(context);
  }

  Widget content(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Sinkronisasi dua arah lokal',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const Text(
            'Data sintetis saja. Profil, revisi dan jadwal dipertukarkan dengan server lokal. Akun awal demo diketahui publik; bukan layanan produksi. Riwayat lama diunggah sebagai pending dan perlu konfirmasi Badan Gizi. Hasil gizi belum dihitung ulang server.',
          ),
          Text(status),
          for (final conflict in widget.repo.syncConflicts)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Konflik ${conflict['key']}: data lokal tetap tersimpan.'),
                Text(
                  'Lokal: ${conflict['local']['name'] ?? conflict['local']['input'] ?? conflict['local']['date']}',
                ),
                Text(
                  'Server: ${conflict['remote']['value']['name'] ?? conflict['remote']['value']['input'] ?? conflict['remote']['value']['date']}',
                ),
                Wrap(
                  children: [
                    TextButton(
                      onPressed: busy
                          ? null
                          : () async {
                              await widget.repo.resolveSyncConflict(
                                conflict['key'],
                                useRemote: true,
                              );
                              final remindersOk = await reconcileReminders();
                              if (mounted) {
                                setState(
                                  () => status = remindersOk
                                      ? 'Versi server dipakai; salinan lokal disimpan di audit.'
                                      : 'Versi server dipakai; periksa izin pengingat.',
                                );
                              }
                              widget.onChanged();
                            },
                      child: const Text('Gunakan server'),
                    ),
                    if (conflict['remote']['kind'] != 'revision' ||
                        [
                          'draft',
                          'approved',
                          'rejected',
                        ].contains(conflict['remote']['value']['status']))
                      TextButton(
                        onPressed: busy
                            ? null
                            : () async {
                                await widget.repo.resolveSyncConflict(
                                  conflict['key'],
                                  useRemote: false,
                                );
                                if (mounted) {
                                  setState(
                                    () => status = 'Versi lokal dipilih; sinkronkan untuk mengirim.',
                                  );
                                }
                                widget.onChanged();
                              },
                        child: Text(
                          conflict['remote']['kind'] == 'revision'
                              ? 'Buat draft koreksi lokal'
                              : 'Pertahankan lokal',
                        ),
                      ),
                  ],
                ),
                if (conflict['remote']['kind'] == 'revision')
                  const Text(
                    'Koreksi lokal membuat revisi draft baru; riwayat server tetap utuh. Bila server masih pending, tunggu review atau gunakan server.',
                  ),
              ],
            ),
          if (demoSyncSupported) ...[
            if (token == null) ...[
              TextField(
                controller: pin,
                obscureText: true,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'PIN sesi sinkronisasi',
                ),
              ),
              FilledButton(
                onPressed: busy ? null : connect,
                child: const Text('Hubungkan sinkronisasi'),
              ),
            ] else
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: busy ? null : synchronize,
                    child: const Text('Sinkronkan sekarang'),
                  ),
                  TextButton(
                    onPressed: busy ? null : changePin,
                    child: const Text('Ganti PIN server'),
                  ),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () async {
                            try {
                              await sendDemoRequest(account, '/sync-logout', {
                                'token': token,
                              });
                            } catch (_) {}
                            if (!mounted) return;
                            timer?.cancel();
                            setState(() {
                              token = null;
                              status = 'Terputus';
                            });
                          },
                    child: const Text('Putuskan sesi lokal'),
                  ),
                ],
              ),
            const Text(
              'Saat tersambung, coba ulang otomatis setiap 30 detik selama layar ini terbuka. Konflik tidak menimpa data lokal.',
            ),
          ] else
            const Text(
              'Gunakan browser localhost 8767 atau Android debug dengan adb reverse.',
            ),
        ],
      ),
    ),
  );
}
