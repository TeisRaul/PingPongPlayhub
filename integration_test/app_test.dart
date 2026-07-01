import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pingpong_playhub/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('PingPong Playhub End-to-End Test', () {
    testWidgets('Verify main flow: Feed, Profile, and Venues', (tester) async {
      // 1. Pornește aplicația
      app.main();
      
      // Așteptăm ca aplicația să se randeze și să treacă de splash screen/login dacă e deja logat
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // 2. Verificăm dacă suntem pe ecranul principal (MainScreen) cu BottomNavigationBar
      final homeIcon = find.byIcon(Icons.home);
      if (homeIcon.evaluate().isNotEmpty) {
        // Suntem logați, putem testa fluxul principal.

        // Mergem pe tab-ul de Prieteni
        final friendsTab = find.byIcon(Icons.people);
        await tester.tap(friendsTab);
        await tester.pumpAndSettle();

        // Navigăm înapoi la Acasă
        await tester.tap(homeIcon);
        await tester.pumpAndSettle();

        // Căutăm tab-ul Săli
        final mapTab = find.byIcon(Icons.map);
        await tester.tap(mapTab);
        await tester.pumpAndSettle();
        
        // Mergem pe Profilul meu
        final profileTab = find.byIcon(Icons.person);
        await tester.tap(profileTab);
        await tester.pumpAndSettle();
        
        // Deschidem sertarul lateral (Drawer)
        final menuIcon = find.byIcon(Icons.menu);
        if (menuIcon.evaluate().isNotEmpty) {
          await tester.tap(menuIcon);
          await tester.pumpAndSettle();
          
          // Închidem drawer-ul făcând tap în afara lui
          await tester.tapAt(const Offset(10, 10));
          await tester.pumpAndSettle();
        }

      } else {
        // Nu suntem logați, verificăm ecranul de Login
        expect(find.text('Continuă cu Google'), findsOneWidget);
        print('Aplicația necesită login manual pentru a rula restul testelor E2E.');
      }
    });
  });
}
