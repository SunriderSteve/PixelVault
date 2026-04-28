import 'package:flutter/material.dart';
import 'services/data_repository.dart';
import 'router.dart'; // exports your GoRouter instance (e.g., `router`)
import 'widgets/pending_changes_fab.dart';
import 'widgets/scroll_to_top_fab.dart' show scrollToTopVisible;

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
      // Global overlay: stacks the pending-changes FAB over every
      // route so it's reachable anywhere in the app without each page
      // having to wire it into its own Scaffold. The FAB self-hides
      // for non-admins and when there's nothing to push.
      //
      // The FAB shares the bottom-right slot with the per-page back-
      // to-top button, so we animate it one slot up whenever
      // [scrollToTopVisible] flips on — the back-to-top FAB takes the
      // bottom slot and pending-changes sits above it.
      builder: (context, child) {
        return Stack(
          children: [
            if (child != null) Positioned.fill(child: child),
            ValueListenableBuilder<bool>(
              valueListenable: scrollToTopVisible,
              builder: (_, lifted, _) => AnimatedPositioned(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                right: 16,
                bottom: lifted ? 88 : 16,
                child: const PendingChangesFab(),
              ),
            ),
          ],
        );
      },
    );
  }
}
