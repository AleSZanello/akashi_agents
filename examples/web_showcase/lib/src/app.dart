import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'demos/registry.dart';
import 'theme.dart';
import 'widgets/demo_view.dart';
import 'widgets/gallery_shell.dart';
import 'widgets/home_view.dart';

/// The showcase app: a [GoRouter] over a persistent [GalleryScaffold].
class AkashiShowcaseApp extends StatelessWidget {
  AkashiShowcaseApp({super.key});

  final _router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) =>
            const GalleryScaffold(selectedId: null, child: HomeView()),
      ),
      GoRoute(
        path: '/demos/:id',
        builder: (context, state) {
          final id = state.pathParameters['id'];
          final demo = id == null ? null : demoById(id);
          if (demo == null) {
            return GalleryScaffold(selectedId: null, child: _NotFound(id: id));
          }
          return GalleryScaffold(
            selectedId: demo.id,
            // Key by id so navigating between demos rebuilds fresh state.
            child: DemoView(key: ValueKey(demo.id), demo: demo),
          );
        },
      ),
    ],
    errorBuilder: (context, state) =>
        const GalleryScaffold(selectedId: null, child: _NotFound()),
  );

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Akashi — agent framework demos',
      debugShowCheckedModeBanner: false,
      theme: buildAkashiTheme(),
      routerConfig: _router,
    );
  }
}

class _NotFound extends StatelessWidget {
  const _NotFound({this.id});
  final String? id;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.travel_explore,
            size: 48,
            color: AkashiColors.textFaint,
          ),
          const SizedBox(height: 12),
          Text(
            id == null ? 'Page not found' : 'No demo named “$id”',
            style: const TextStyle(
              fontSize: 18,
              color: AkashiColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => context.go('/'),
            child: const Text('Back to demos'),
          ),
        ],
      ),
    );
  }
}
