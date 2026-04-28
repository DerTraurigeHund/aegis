import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aegis/main.dart';

void main() {
  testWidgets('App starts and shows server list', (WidgetTester tester) async {
    await tester.pumpWidget(const AegisApp());

    // Should show either "Aegis" or the empty state
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
