import 'package:go_router/go_router.dart';
import 'pages/learn_equip_list_page.dart';
import 'pages/learn_equip_detail_page.dart';
import 'pages/scenario_list_page.dart';
import 'pages/scenario_detail_page.dart';
import 'pages/homepage.dart';

final GoRouter appRouter = GoRouter(
  routes: [
    GoRoute(path: '/', builder: (_, _) => const HomePage()),
    GoRoute(path: '/equip', builder: (_, _) => const EquipListPage()),
    GoRoute(
      path: '/equip/:id',
      builder: (_, state) =>
          EquipDetailPage(itemId: state.pathParameters['id']!),
    ),
    GoRoute(path: '/scenarios', builder: (_, _) => const ScenarioListPage()),
    GoRoute(
      path: '/scenarios/:sid',
      builder: (_, state) =>
          ScenarioDetailPage(scenarioId: state.pathParameters['sid']!),
    ),
  ],
);
