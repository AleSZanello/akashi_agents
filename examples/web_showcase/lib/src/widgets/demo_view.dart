import 'package:flutter/material.dart';

import '../demos/demo.dart';
import '../theme.dart';
import 'code_view.dart';

/// Renders a single [Demo]: a header, a Live/Code toggle, and the content. The
/// live demo is kept alive across the toggle (via [IndexedStack]) so switching
/// to the code and back never resets the running conversation.
class DemoView extends StatefulWidget {
  const DemoView({super.key, required this.demo});
  final Demo demo;

  @override
  State<DemoView> createState() => _DemoViewState();
}

class _DemoViewState extends State<DemoView> {
  int _tab = 0; // 0 = live, 1 = code

  @override
  Widget build(BuildContext context) {
    final demo = widget.demo;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PillarTag(demo.pillar),
              const SizedBox(height: 10),
              Text(
                demo.title,
                style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: AkashiColors.textPrimary),
              ),
              const SizedBox(height: 10),
              Text(
                demo.blurb,
                style: const TextStyle(
                    fontSize: 14.5,
                    height: 1.55,
                    color: AkashiColors.textSecondary),
              ),
              const SizedBox(height: 20),
              _Toggle(
                tab: _tab,
                onChanged: (t) => setState(() => _tab = t),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: IndexedStack(
                  index: _tab,
                  sizing: StackFit.expand,
                  children: [
                    _LivePanel(child: Builder(builder: demo.builder)),
                    SingleChildScrollView(child: CodeView(demo.source)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LivePanel extends StatelessWidget {
  const _LivePanel({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AkashiColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AkashiColors.border),
      ),
      padding: const EdgeInsets.all(16),
      child: child,
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({required this.tab, required this.onChanged});
  final int tab;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AkashiColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AkashiColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Seg(label: 'Live demo', icon: Icons.play_arrow_rounded, selected: tab == 0, onTap: () => onChanged(0)),
          _Seg(label: 'Code', icon: Icons.code, selected: tab == 1, onTap: () => onChanged(1)),
        ],
      ),
    );
  }
}

class _Seg extends StatelessWidget {
  const _Seg({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AkashiColors.primary : Colors.transparent,
      borderRadius: BorderRadius.circular(7),
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(icon,
                  size: 16,
                  color: selected ? Colors.white : AkashiColors.textSecondary),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : AkashiColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PillarTag extends StatelessWidget {
  const _PillarTag(this.pillar);
  final Pillar pillar;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AkashiColors.primary.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AkashiColors.primary.withValues(alpha: 0.4)),
      ),
      child: Text(
        pillar.label,
        style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: AkashiColors.primary),
      ),
    );
  }
}
