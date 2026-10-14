import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigibas_rasp/main.dart';

void main() {
  testWidgets('Material3 preserves existing seed theme', (tester) async {
    await tester.pumpWidget(const MyApp());
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.title, 'SI-GIBAS RASP');
    expect(app.theme!.useMaterial3, isTrue);
    expect(find.byType(Bootstrap), findsOneWidget);
  });
  testWidgets('bootstrap pending does not seed or reset data', (tester) async {
    await tester.pumpWidget(const MyApp());
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
  });
}
