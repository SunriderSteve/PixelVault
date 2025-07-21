import 'package:flutter/material.dart';
import 'router.dart';
import 'services/data_repository.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DataRepository().init(); // load YAML before UI starts
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'PixelVault',
      routerConfig: appRouter,
      theme: ThemeData(useMaterial3: true),
    );
  }
}
