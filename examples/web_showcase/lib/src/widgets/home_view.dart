import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../demos/demo.dart';
import '../demos/registry.dart';
import '../theme.dart';

/// The landing page: a hero plus a grid of demo cards.
class HomeView extends StatelessWidget {
  const HomeView({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(28, 40, 28, 40),
          children: [
            const _Hero(),
            const SizedBox(height: 40),
            const Text(
              'Explore the demos',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AkashiColors.textPrimary),
            ),
            const SizedBox(height: 4),
            const Text(
              'Each runs entirely in your browser on a scripted fake model.',
              style: TextStyle(color: AkashiColors.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 20),
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth > 720 ? 2 : 1;
                return GridView.count(
                  crossAxisCount: columns,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 14,
                  childAspectRatio: columns == 2 ? 3.0 : 4.2,
                  children: [
                    for (final demo in kDemos) _DemoCard(demo: demo),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AkashiColors.primary.withValues(alpha: 0.18),
            AkashiColors.accent.withValues(alpha: 0.06),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AkashiColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Akashi',
            style: TextStyle(
              fontSize: 44,
              fontWeight: FontWeight.w900,
              color: AkashiColors.textPrimary,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'A provider-neutral agent framework for Dart & Flutter.',
            style: TextStyle(
                fontSize: 18,
                color: AkashiColors.textPrimary,
                fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 14),
          const Text(
            'Multi-agent orchestration, durable execution, and a genuinely '
            'Flutter-reactive agent loop — the lanes most Dart agent tools '
            'under-serve. Everything on this site runs live, in your browser, '
            'on a fake model. No API keys, no backend.',
            style: TextStyle(
                fontSize: 14.5,
                height: 1.6,
                color: AkashiColors.textSecondary),
          ),
          const SizedBox(height: 22),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: () => context.go('/demos/${kDemos.first.id}'),
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                label: const Text('Try the first demo'),
                style: FilledButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => context.go('/demos/durable-resume'),
                icon: const Icon(Icons.bedtime_outlined, size: 18),
                label: const Text('See durable execution'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AkashiColors.textPrimary,
                  side: const BorderSide(color: AkashiColors.border),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DemoCard extends StatelessWidget {
  const _DemoCard({required this.demo});
  final Demo demo;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AkashiColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => context.go('/demos/${demo.id}'),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AkashiColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AkashiColors.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(demo.icon, color: AkashiColors.primary, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(demo.title,
                        style: const TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w700,
                            color: AkashiColors.textPrimary)),
                    const SizedBox(height: 3),
                    Text(demo.tagline,
                        style: const TextStyle(
                            fontSize: 12.5, color: AkashiColors.textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward,
                  size: 16, color: AkashiColors.textFaint),
            ],
          ),
        ),
      ),
    );
  }
}
