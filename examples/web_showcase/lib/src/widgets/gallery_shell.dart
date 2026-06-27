import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../demos/demo.dart';
import '../demos/registry.dart';
import '../theme.dart';

const kGithubUrl = 'https://github.com/Alezanello/akashi_agents';
const kPubUrl = 'https://pub.dev/packages/akashi';

/// The persistent shell: an Akashi-branded sidebar of demos beside [child].
/// Collapses the sidebar into a drawer below 900px.
class GalleryScaffold extends StatelessWidget {
  const GalleryScaffold({super.key, required this.selectedId, required this.child});

  /// The currently-open demo id, or null on the home page.
  final String? selectedId;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final sidebar = _Sidebar(selectedId: selectedId);

    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            SizedBox(width: 300, child: sidebar),
            const VerticalDivider(width: 1, color: AkashiColors.border),
            Expanded(child: child),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AkashiColors.background,
        title: const _Wordmark(compact: true),
      ),
      drawer: Drawer(
        backgroundColor: AkashiColors.background,
        child: sidebar,
      ),
      body: child,
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.selectedId});
  final String? selectedId;

  @override
  Widget build(BuildContext context) {
    final byPillar = <Pillar, List<Demo>>{};
    for (final demo in kDemos) {
      byPillar.putIfAbsent(demo.pillar, () => []).add(demo);
    }

    return Container(
      color: AkashiColors.background,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 8),
              child: InkWell(
                onTap: () => context.go('/'),
                child: const _Wordmark(),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                'Live, in-browser demos — every one runs on a fake model. No API keys.',
                style: TextStyle(
                    color: AkashiColors.textFaint, fontSize: 12, height: 1.4),
              ),
            ),
            const Divider(height: 1, color: AkashiColors.border),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 10),
                children: [
                  for (final pillar in Pillar.values)
                    if (byPillar[pillar] != null) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
                        child: Text(
                          pillar.label.toUpperCase(),
                          style: const TextStyle(
                            color: AkashiColors.textFaint,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.1,
                          ),
                        ),
                      ),
                      for (final demo in byPillar[pillar]!)
                        _SidebarItem(
                          demo: demo,
                          selected: demo.id == selectedId,
                        ),
                    ],
                ],
              ),
            ),
            const Divider(height: 1, color: AkashiColors.border),
            const _SidebarLinks(),
          ],
        ),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({required this.demo, required this.selected});
  final Demo demo;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: Material(
        color: selected
            ? AkashiColors.primary.withValues(alpha: 0.16)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => context.go('/demos/${demo.id}'),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              children: [
                Icon(demo.icon,
                    size: 18,
                    color: selected
                        ? AkashiColors.primary
                        : AkashiColors.textSecondary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        demo.title,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w500,
                          color: selected
                              ? AkashiColors.textPrimary
                              : AkashiColors.textPrimary,
                        ),
                      ),
                      Text(
                        demo.tagline,
                        style: const TextStyle(
                            fontSize: 11.5, color: AkashiColors.textFaint),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SidebarLinks extends StatelessWidget {
  const _SidebarLinks();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          _LinkButton(
              icon: Icons.code_rounded, label: 'GitHub', url: kGithubUrl),
          const SizedBox(width: 8),
          _LinkButton(
              icon: Icons.inventory_2_outlined, label: 'pub.dev', url: kPubUrl),
        ],
      ),
    );
  }
}

class _LinkButton extends StatelessWidget {
  const _LinkButton(
      {required this.icon, required this.label, required this.url});
  final IconData icon;
  final String label;
  final String url;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () => launchUrl(Uri.parse(url)),
      icon: Icon(icon, size: 15),
      label: Text(label, style: const TextStyle(fontSize: 12.5)),
      style: OutlinedButton.styleFrom(
        foregroundColor: AkashiColors.textSecondary,
        side: const BorderSide(color: AkashiColors.border),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
    );
  }
}

/// The Akashi wordmark: a small glyph + name.
class _Wordmark extends StatelessWidget {
  const _Wordmark({this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AkashiColors.primary, AkashiColors.accent],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.auto_awesome, size: 17, color: Colors.white),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Akashi',
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AkashiColors.textPrimary,
                    height: 1.0)),
            if (!compact)
              const Text('agents for Dart & Flutter',
                  style:
                      TextStyle(fontSize: 11, color: AkashiColors.textFaint)),
          ],
        ),
      ],
    );
  }
}
