import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aegis/main.dart';
import 'package:aegis/theme/app_theme.dart';

void main() {
  testWidgets('AegisApp creates a MaterialApp with dark theme', (WidgetTester tester) async {
    await tester.pumpWidget(const AegisApp());

    expect(find.byType(MaterialApp), findsOneWidget);

    // Verify the theme is set
    final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(materialApp.title, equals('Aegis'));
    expect(materialApp.debugShowCheckedModeBanner, isFalse);
  });
}
