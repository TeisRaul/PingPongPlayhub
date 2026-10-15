import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// Ecranul sălii pentru vouchere / coduri de reducere.
/// Codurile se salvează în `vouchers/{uid}_{COD}`; jucătorii le introduc la rezervare,
/// iar verificarea și contorul de folosiri sunt făcute pe server (functions/vouchers.js).
class VenueVouchersScreen extends StatelessWidget {
  const VenueVouchersScreen({super.key});

  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  String _describe(Map<String, dynamic> v) {
    final fixed = v['type'] == 'fixed';
    final value = ((v['value'] as num?) ?? 0).toDouble();
    final what = fixed ? '-${value.toStringAsFixed(0)} RON' : '-${value.toStringAsFixed(0)}%';
    final from = (v['validFrom'] ?? '').toString();
    final to = (v['validTo'] ?? '').toString();
    final period = (from.isEmpty && to.isEmpty) ? 'fără limită de timp' : '${from.isEmpty ? '...' : from} → ${to.isEmpty ? '...' : to}';
    final maxUses = ((v['maxUses'] as num?) ?? 0).toInt();
    final used = ((v['usedCount'] as num?) ?? 0).toInt();
    final uses = maxUses > 0 ? 'folosit $used/$maxUses' : 'folosit $used (nelimitat)';
    final extra = [
      if (v['perUserOnce'] == true) 'o singură dată per jucător',
      if (((v['minAmount'] as num?) ?? 0) > 0) 'minim ${((v['minAmount'] as num).toDouble()).toStringAsFixed(0)} RON',
    ];
    return '$what · $period\n$uses${extra.isEmpty ? '' : '\n${extra.join(' · ')}'}';
  }

  Future<void> _add(BuildContext context) async {
    final created = await showDialog<Map<String, dynamic>>(context: context, builder: (_) => const _VoucherDialog());
    if (created == null || !context.mounted) return;
    final code = created['code'] as String;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final existing = await FirebaseFirestore.instance
          .collection('vouchers')
          .where('venueId', isEqualTo: _uid)
          .where('code', isEqualTo: code)
          .limit(1)
          .get();
      if (existing.docs.isNotEmpty) {
        messenger.showSnackBar(SnackBar(content: Text('Codul $code există deja.'), backgroundColor: Colors.redAccent));
        return;
      }
      await FirebaseFirestore.instance.collection('vouchers').doc('${_uid}_$code').set({
        ...created,
        'venueId': _uid,
        'usedCount': 0,
        'active': true,
        'createdAt': FieldValue.serverTimestamp(),
      });
      messenger.showSnackBar(SnackBar(content: Text('Codul $code a fost creat.'), backgroundColor: Colors.green));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Eroare la salvare: $e'), backgroundColor: Colors.redAccent));
    }
  }

  Future<void> _delete(BuildContext context, DocumentSnapshot<Map<String, dynamic>> d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text('Ștergi codul ${d.data()?['code'] ?? ''}?', style: TextStyle(color: AppColors.text)),
        content: Text('Jucătorii nu îl vor mai putea folosi. Rezervările deja făcute cu el rămân neschimbate.', style: TextStyle(color: AppColors.text70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Înapoi', style: TextStyle(color: AppColors.muted))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Șterge', style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (ok == true) await d.reference.delete();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.card,
        iconTheme: IconThemeData(color: AppColors.accent),
        title: Text('Vouchere', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.accent,
        foregroundColor: AppColors.onAccent,
        onPressed: () => _add(context),
        icon: const Icon(Icons.add),
        label: const Text('Cod nou'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('vouchers').where('venueId', isEqualTo: _uid).snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Eroare: ${snap.error}', style: const TextStyle(color: Colors.redAccent))));
          }
          if (!snap.hasData) return Center(child: CircularProgressIndicator(color: AppColors.accent));
          final docs = snap.data!.docs.toList()
            ..sort((a, b) {
              final ta = a.data()['createdAt'];
              final tb = b.data()['createdAt'];
              if (ta is Timestamp && tb is Timestamp) return tb.compareTo(ta);
              return 0;
            });
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(
                  'Creează coduri pe care le dai jucătorilor (pe rețele sociale, în sală, prin email). '
                  'Jucătorul îl introduce la rezervare și plătește prețul redus. Reducerea se aplică prețului mesei, nu serviciilor extra sau barului. '
                  'Un cod poate avea perioadă de valabilitate, număr maxim de folosiri și limită de o folosire per jucător.',
                  style: TextStyle(color: AppColors.text54, fontSize: 12.5),
                ),
              ),
              const SizedBox(height: 14),
              if (docs.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Nu ai niciun cod. Apasă „Cod nou”, de exemplu VARA20 pentru -20% în iulie.',
                      textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
                ),
              for (final d in docs)
                Card(
                  color: AppColors.card,
                  margin: const EdgeInsets.only(bottom: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: d.data()['active'] == false ? AppColors.border : AppColors.accent.withValues(alpha: 0.4)),
                  ),
                  child: ListTile(
                    isThreeLine: true,
                    leading: Icon(Icons.confirmation_number_outlined, color: d.data()['active'] == false ? AppColors.muted : AppColors.accent),
                    title: Row(
                      children: [
                        Text('${d.data()['code'] ?? ''}', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold, letterSpacing: 1)),
                        const SizedBox(width: 6),
                        InkWell(
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: '${d.data()['code'] ?? ''}'));
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cod copiat.')));
                          },
                          child: Icon(Icons.copy, size: 16, color: AppColors.text54),
                        ),
                      ],
                    ),
                    subtitle: Text(_describe(d.data()), style: TextStyle(color: AppColors.text54, fontSize: 12.5)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Switch(
                          value: d.data()['active'] != false,
                          onChanged: (v) => d.reference.update({'active': v}),
                        ),
                        IconButton(icon: const Icon(Icons.delete_outline, color: Colors.redAccent), onPressed: () => _delete(context, d)),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _VoucherDialog extends StatefulWidget {
  const _VoucherDialog();

  @override
  State<_VoucherDialog> createState() => _VoucherDialogState();
}

class _VoucherDialogState extends State<_VoucherDialog> {
  final _code = TextEditingController();
  final _value = TextEditingController();
  final _maxUses = TextEditingController(text: '0');
  final _minAmount = TextEditingController(text: '0');
  String _type = 'percent';
  bool _perUserOnce = true;
  DateTime? _from;
  DateTime? _to;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    _value.dispose();
    _maxUses.dispose();
    _minAmount.dispose();
    super.dispose();
  }

  String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  void _generate() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random.secure();
    setState(() => _code.text = List.generate(8, (_) => chars[r.nextInt(chars.length)]).join());
  }

  Future<void> _pickDate(bool from) async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: (from ? _from : _to) ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
    );
    if (d != null) setState(() => from ? _from = d : _to = d);
  }

  void _submit() {
    final code = _code.text.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');
    if (!RegExp(r'^[A-Z0-9_-]{3,24}$').hasMatch(code)) {
      setState(() => _error = 'Codul trebuie să aibă 3-24 caractere: litere, cifre, - sau _.');
      return;
    }
    final value = double.tryParse(_value.text.trim().replaceAll(',', '.'));
    if (value == null || value <= 0) {
      setState(() => _error = 'Introdu o valoare validă a reducerii.');
      return;
    }
    if (_type == 'percent' && value > 100) {
      setState(() => _error = 'Reducerea nu poate depăși 100%.');
      return;
    }
    final maxUses = int.tryParse(_maxUses.text.trim()) ?? 0;
    final minAmount = double.tryParse(_minAmount.text.trim().replaceAll(',', '.')) ?? 0;
    if (_from != null && _to != null && _to!.isBefore(_from!)) {
      setState(() => _error = 'Perioada este inversată.');
      return;
    }
    Navigator.pop(context, {
      'code': code,
      'type': _type,
      'value': value,
      'validFrom': _from == null ? '' : _ymd(_from!),
      'validTo': _to == null ? '' : _ymd(_to!),
      'maxUses': maxUses < 0 ? 0 : maxUses,
      'perUserOnce': _perUserOnce,
      'minAmount': minAmount < 0 ? 0 : minAmount,
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.card,
      title: Text('Cod de reducere', style: TextStyle(color: AppColors.text)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _code,
                    textCapitalization: TextCapitalization.characters,
                    style: TextStyle(color: AppColors.text),
                    decoration: const InputDecoration(labelText: 'Cod (ex. VARA20)'),
                  ),
                ),
                IconButton(icon: Icon(Icons.casino_outlined, color: AppColors.accent), tooltip: 'Generează', onPressed: _generate),
              ],
            ),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'percent', label: Text('Reducere %')),
                ButtonSegment(value: 'fixed', label: Text('Sumă fixă')),
              ],
              selected: {_type},
              onSelectionChanged: (s) => setState(() => _type = s.first),
            ),
            TextField(
              controller: _value,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: TextStyle(color: AppColors.text),
              decoration: InputDecoration(labelText: _type == 'percent' ? 'Reducere (%)' : 'Reducere (RON)'),
            ),
            const SizedBox(height: 8),
            Text('Valabil (opțional)', style: TextStyle(color: AppColors.text70, fontSize: 12)),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => _pickDate(true),
                    child: Text(_from == null ? 'De la data' : _ymd(_from!), style: TextStyle(color: AppColors.accent)),
                  ),
                ),
                Expanded(
                  child: TextButton(
                    onPressed: () => _pickDate(false),
                    child: Text(_to == null ? 'Până la data' : _ymd(_to!), style: TextStyle(color: AppColors.accent)),
                  ),
                ),
              ],
            ),
            TextField(
              controller: _maxUses,
              keyboardType: TextInputType.number,
              style: TextStyle(color: AppColors.text),
              decoration: const InputDecoration(labelText: 'Număr maxim de folosiri (0 = nelimitat)'),
            ),
            TextField(
              controller: _minAmount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: TextStyle(color: AppColors.text),
              decoration: const InputDecoration(labelText: 'Preț minim al mesei (RON, 0 = fără minim)'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('O singură folosire per jucător', style: TextStyle(color: AppColors.text, fontSize: 14)),
              value: _perUserOnce,
              onChanged: (v) => setState(() => _perUserOnce = v),
            ),
            if (_error != null) Text(_error!, style: const TextStyle(color: Colors.redAccent)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text('Renunță', style: TextStyle(color: AppColors.muted))),
        TextButton(onPressed: _submit, child: Text('Creează', style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold))),
      ],
    );
  }
}
