import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'services/database_service.dart';
import 'services/api_service.dart';
import 'services/crypto.dart';
import 'screens/server_list_screen.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dbService = DatabaseService();
  await dbService.database;
  runApp(
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
}

class AegisApp extends StatelessWidget {
  const AegisApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Aegis',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const ServerListScreen(),
    );
  }
}
