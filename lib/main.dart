import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'services/data_repository.dart';
import 'pages/homepage.dart';
import 'pages/learn_equip_list_page.dart';
import 'pages/learn_equip_detail_page.dart';
import 'pages/scenario_list_page.dart';
import 'pages/scenario_detail_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DataRepository().init(); // load YAML before UI starts
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (context, state) => const HomePage()),
        GoRoute(
          path: '/equip',
          builder: (context, state) => const EquipListPage(),
        ),
        GoRoute(
          path: '/equip/:id',
          builder: (context, state) {
            final id = state.pathParameters['id']!;
            return EquipDetailPage(itemId: id);
          },
        ),
        GoRoute(
          path: '/scenarios',
          builder: (context, state) => const ScenarioListPage(),
        ),
        GoRoute(
          path: '/scenarios/:id',
          builder: (context, state) {
            final id = state.pathParameters['id']!;
            return ScenarioDetailPage(scenarioId: id);
          },
        ),
        // Stub for inventory route until implemented:
        GoRoute(
          path: '/inventory',
          builder: (context, state) => Scaffold(
            appBar: AppBar(title: const Text('Inventory List')),
            body: const Center(child: Text('Inventory coming soon')),
          ),
        ),
      ],
    );

    return MaterialApp.router(
      title: 'PixelVault',
      routerConfig: router,
      theme: ThemeData(primarySwatch: Colors.blue),
    );
  }
}
