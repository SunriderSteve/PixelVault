// PixelVault — go_router configuration.
//
// Declares every route in the app. Keep this file flat: path, builder,
// and nothing else. Screen logic lives in the page widgets it refers
// to. If you add a route, also update the `Route map` block below so
// future readers don't have to scan the route list to get the shape
// of the app.
//
// Route map:
//   /                              → HomePage
//   /learn                         → LearningListPage
//   /learn/equip-guides            → LearnEquipListPage
//   /learn/equip-guides/:id        → EquipDetailPage
//   /learn/videography-guides      → LearnVideographyListPage
//   /learn/videography-guides/:id  → VideographyDetailPage
//   /scenarios                     → ScenarioListPage
//   /scenarios/:id                 → ScenarioDetailPage
//   /inventory                     → InventoryListPage
//   /shoots                        → ProductionShootsPage
//   /shoots/:name                  → ProductionShootDetailPage
//
// Hero tag contracts on the home page rely on these paths staying
// stable — renaming a route also requires updating the matching
// destination page's Hero tag so the transition doesn't break.

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'pages/homepage.dart';
import 'pages/inventory_list_page.dart';
import 'pages/learn_equip_detail_page.dart';
import 'pages/learn_equip_list_page.dart';
import 'pages/learn_videography_detail_page.dart';
import 'pages/learn_videography_list_page.dart';
import 'pages/production_shoot_detail_page.dart';
import 'pages/production_shoots_page.dart';
import 'pages/scenario_detail_page.dart';
import 'pages/scenario_list_page.dart';

/// Root navigator key. Exposed so widgets that live above the
/// Navigator (e.g. the global pending-changes FAB injected via
/// `MaterialApp.builder`) can reach into the navigation tree to show
/// dialogs — those widgets' own contexts sit ABOVE the Navigator and
/// `Navigator.of(context)` would otherwise fail to resolve.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

/// Top-level router for the app. Wired into `MaterialApp.router` in
/// `main.dart` — this is the single source of truth for navigation.
final GoRouter appRouter = GoRouter(
  navigatorKey: rootNavigatorKey,
  routes: [
    // ── Home ──────────────────────────────────────────────────────
    GoRoute(path: '/', builder: (_, _) => const HomePage()),
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

    // ── Scenarios ─────────────────────────────────────────────────
    GoRoute(
      path: '/scenarios',
      builder: (context, state) => const ScenarioListPage(),
    ),
    GoRoute(
      path: '/scenarios/:id',
      builder: (context, state) =>
          ScenarioDetailPage(id: state.pathParameters['id']!),
    ),

    // ── Inventory ─────────────────────────────────────────────────
    GoRoute(
      path: '/inventory',
      builder: (context, state) => const InventoryListPage(),
    ),

    // ── Production Shoots ────────────────────────────────────────
    GoRoute(path: '/shoots', builder: (_, _) => const ProductionShootsPage()),
    GoRoute(
      path: '/shoots/:name',
      builder: (_, state) => ProductionShootDetailPage(
        shootName: Uri.decodeComponent(state.pathParameters['name']!),
      ),
    ),
  ],
);
