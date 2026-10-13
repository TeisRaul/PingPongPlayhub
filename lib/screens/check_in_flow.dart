import 'package:flutter/material.dart';

import '../services/checkin_service.dart';
import '../utils/hour_utils.dart';
import 'change_table_dialog.dart';
import 'qr_scanner_screen.dart';

enum CheckInAction { cancel, approve, wait, noShow, changeTable }

/// Fluxul complet de check-in: scanează QR (sau cod introdus manual), validează
/// biletul, arată detaliile și marchează prezența.
///
/// Folosit de sală (doar pentru meciurile ei) și de admin (pentru orice meci).
class CheckInFlow {
  CheckInFlow._();

  /// După atâtea minute de întârziere sala poate elibera masa (No-Show).
  static const int _noShowAfterMinutes = 15;

  /// Deschide camera, apoi procesează codul scanat.
  static Future<void> scan(
    BuildContext context, {
    String? venueId,
    bool isAdmin = false,
  }) async {
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const QrScannerScreen()),
    );
    if (code == null || !context.mounted) return;
    await processCode(context, code, venueId: venueId, isAdmin: isAdmin);
  }

  /// Validează codul și cere confirmarea check-in-ului.
  static Future<void> processCode(
    BuildContext context,
    String code, {
    String? venueId,
    bool isAdmin = false,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await CheckInService.lookup(code, venueId: venueId, isAdmin: isAdmin);
      if (result.status != CheckInStatus.ok) {
        messenger.showSnackBar(SnackBar(
          content: Text(CheckInService.messageFor(result.status, result.data)),
          backgroundColor: result.status == CheckInStatus.alreadyCheckedIn ? Colors.orange : Colors.red,
        ));
        return;
      }

      final matchId = result.matchId!;
      final data = result.data!;
      final price = (data['price'] as num?)?.toDouble() ?? 0.0;
      final paymentMethod = (data['paymentMethod'] ?? 'Cash la locație').toString();
      final isPaid = paymentMethod.contains('Card') || data['paymentStatus'] == 'confirmed';
      final busy = result.tableLikelyBusy;

      if (!context.mounted) return;
      final action = await showDialog<CheckInAction>(
        context: context,
        builder: (ctx) => AlertDialog(
          scrollable: true,
          backgroundColor: const Color(0xFF131A2A),
          title: const Text('Aprobare Check-in',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isAdmin)
                Text('Sală: ${data['locationName'] ?? '-'}', style: const TextStyle(color: Colors.white70)),
              Text('Jucător: ${data['hostUsername'] ?? 'Host'}', style: const TextStyle(color: Colors.white70)),
              Text(
                'Data: ${data['date']} | ${formatHour(data['startHour'])} - ${formatHour(data['endHour'])}',
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 6),
              Text(
                'Masa ${data['tableId'] ?? '-'}',
                style: const TextStyle(color: Color(0xFF00E5FF), fontSize: 22, fontWeight: FontWeight.bold),
              ),
              if (result.minutesEarly > 0) ...[
                const SizedBox(height: 6),
                Text(
                  'A venit cu ${result.minutesEarly} min mai devreme '
                  '(rezervare de la ${formatHour(data['startHour'])}).',
                  style: const TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold),
                ),
                if (result.overlaps.isEmpty)
                  const Text('Masa nu are altă rezervare în acest interval.',
                      style: TextStyle(color: Colors.green)),
              ],
              for (final m in result.overlaps)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Masa e rezervată și de ${m['hostUsername'] ?? 'alt jucător'}, '
                    '${formatHour(m['startHour'])} - ${formatHour(m['endHour'])} '
                    '(${m['checkedIn'] == true ? 'check-in efectuat, probabil ocupată' : 'fără check-in'})',
                    style: TextStyle(
                      color: m['checkedIn'] == true ? Colors.redAccent : Colors.orangeAccent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              if (result.minutesLate > 0) ...[
                const SizedBox(height: 6),
                Text(
                  'A întârziat ${result.minutesLate} min, mai are ${result.minutesLeft} min din rezervare.',
                  style: TextStyle(
                    color: result.minutesLate >= _noShowAfterMinutes ? Colors.redAccent : Colors.orangeAccent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (result.minutesLate >= _noShowAfterMinutes)
                  const Text('Întârziere mare: poți elibera masa (No-Show).',
                      style: TextStyle(color: Colors.redAccent)),
              ],
              if (data['waiting'] == true) ...[
                const SizedBox(height: 6),
                const Text('Era la așteptarea mesei.', style: TextStyle(color: Colors.orangeAccent)),
              ],
              const SizedBox(height: 10),
              if (!isPaid)
                Text(
                  'Atenție: trebuie să încasezi ${price.toStringAsFixed(0)} RON (Cash)',
                  style: const TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold),
                )
              else
                const Text('Plata este deja achitată / confirmată.',
                    style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, CheckInAction.cancel),
              child: const Text('Anulează', style: TextStyle(color: Colors.grey)),
            ),
            if (data['tableId'] != null)
              TextButton(
                onPressed: () => Navigator.pop(ctx, CheckInAction.changeTable),
                child: const Text('Schimbă masa', style: TextStyle(color: Color(0xFF00E5FF))),
              ),
            if (result.overlaps.isNotEmpty)
              TextButton(
                onPressed: () => Navigator.pop(ctx, CheckInAction.wait),
                child: const Text('Așteaptă masa', style: TextStyle(color: Colors.orangeAccent)),
              ),
            if (result.minutesLate >= _noShowAfterMinutes)
              TextButton(
                onPressed: () => Navigator.pop(ctx, CheckInAction.noShow),
                child: const Text('No-Show', style: TextStyle(color: Colors.redAccent)),
              ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: busy ? Colors.redAccent : const Color(0xFF00E5FF),
                foregroundColor: busy ? Colors.white : Colors.black,
              ),
              onPressed: () => Navigator.pop(ctx, CheckInAction.approve),
              child: Text(busy ? 'Aprob oricum' : (isPaid ? 'Aprob intrarea' : 'Am încasat & aprob')),
            ),
          ],
        ),
      );
      switch (action) {
        case CheckInAction.approve:
          await CheckInService.confirm(
            matchId,
            markPaid: !isPaid,
            minutesLate: result.minutesLate,
            approvedDespiteBusy: busy,
          );
          messenger.showSnackBar(const SnackBar(
            content: Text('Check-in realizat cu succes!'),
            backgroundColor: Colors.green,
          ));
          break;
        case CheckInAction.wait:
          await CheckInService.hold(matchId);
          messenger.showSnackBar(const SnackBar(
            content: Text('Jucătorul așteaptă masa. Apasă „Check-in" pe rezervare când se eliberează.'),
            backgroundColor: Colors.orange,
          ));
          break;
        case CheckInAction.noShow:
          await CheckInService.markNoShow(matchId, (data['hostUid'] ?? '').toString());
          messenger.showSnackBar(const SnackBar(
            content: Text('Marcat No-Show. Rezervarea a fost anulată, masa e liberă.'),
            backgroundColor: Colors.orange,
          ));
          break;
        case CheckInAction.changeTable:
          if (!context.mounted) return;
          final changed = await ChangeTableDialog.show(context, matchId, data);
          if (changed) {
            messenger.showSnackBar(const SnackBar(
              content: Text('Masa a fost schimbată. Jucătorul a fost anunțat.'),
              backgroundColor: Colors.green,
            ));
            if (!context.mounted) return;
            // Redeschide aprobarea cu masa nouă.
            await processCode(context, matchId, venueId: venueId, isAdmin: isAdmin);
          }
          break;
        case CheckInAction.cancel:
        case null:
          break;
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Eroare: $e'), backgroundColor: Colors.red));
    }
  }
}
