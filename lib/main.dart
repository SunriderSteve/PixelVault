import 'package:flutter/material.dart';
import 'services/data_repository.dart';
import 'router.dart'; // exports your GoRouter instance (e.g., `router`)

Future<void> main() async {
  // Needed because we're doing async work before runApp()
  WidgetsFlutterBinding.ensureInitialized();

  // Load admin config, static YAMLs, then the overlay once; start polling after.
  await DataRepository().ensureInitialized();

  runApp(const PixelVaultApp());
}

class PixelVaultApp extends StatelessWidget {
  const PixelVaultApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'PixelVault',
      routerConfig: appRouter,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0047BB)),
        useMaterial3: true,
      ),
    );
  }
}
