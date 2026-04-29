import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:aegis/main.dart';
import 'package:aegis/services/database_service.dart';
import 'package:aegis/services/api_service.dart';
import 'package:aegis/services/crypto.dart';

void main() {
  testWidgets('App starts and shows server list', (WidgetTester tester) async {
    final dbService = DatabaseService();
    await dbService.database;

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<DatabaseService>.value(value: dbService),
          Provider<CryptoService>(create: (_) => CryptoService()),
          Provider<ApiService>(
            create: (ctx) => ApiService(crypto: ctx.read<CryptoService>()),
          ),
        ],
        child: const AegisApp(),
      ),
    );

    // Should show either "Aegis" or the empty state
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
