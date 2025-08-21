import 'package:go_router/go_router.dart';
import 'pages/learning_list_page.dart';
import 'pages/learn_equip_list_page.dart';
import 'pages/learn_videography_list_page.dart';
import 'pages/learn_videography_detail_page.dart';
import 'pages/learn_equip_detail_page.dart';
import 'pages/scenario_list_page.dart';
import 'pages/scenario_detail_page.dart';
import 'pages/homepage.dart';

final GoRouter appRouter = GoRouter(
  routes: [
    // Home
    GoRoute(path: '/', builder: (_, _) => const HomePage()),

    // Learning Guides
    GoRoute(path: '/learn', builder: (_, _) => const LearningListPage()),
    GoRoute(
      path: '/learn/equip-guides',
      builder: (_, _) => const LearnEquipListPage(),
    ),
    GoRoute(
      path: '/learn/equip-guides/:id',
      builder: (_, state) =>
          EquipDetailPage(itemID: state.pathParameters['id']!),
    ),
    GoRoute(
      path: '/learn/videography-guides',
      builder: (_, _) => const LearnVideographyListPage(),
    ),
    GoRoute(
      path: '/learn/videography-guides/:id',
      builder: (_, state) =>
          VideographyDetailPage(itemID: state.pathParameters['id']!),
    ),

    GoRoute(path: '/scenarios', builder: (_, _) => const ScenarioListPage()),
    // GoRoute(
    //   path: '/scenarios/:sid',
    //   builder: (_, state) =>
    //       ScenarioDetailPage(scenarioId: state.pathParameters['sid']!),
    // ),
  ],
);
