import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pingpong_playhub/main.dart' as app;

void main() {
  testWidgets('Verificare ecran de Login - Test Web/Headless', (WidgetTester tester) async {
    // Încărcăm aplicația în mediul de testare
    app.main();
    
    // Așteptăm să se termine animațiile și randerizarea
    await tester.pumpAndSettle();

    // Verificăm dacă textele de pe ecranul de Login există
    expect(find.text('Logează-te cu Google'), findsOneWidget);
    expect(find.text('LOG IN'), findsOneWidget);
    
    // Putem chiar să testăm interacțiuni simple (fără baze de date reale)
    // De exemplu, verificăm dacă există iconița de Google
    expect(find.byType(ElevatedButton), findsWidgets);
  });
}
