import 'package:flutter/material.dart';

/// The three pillars the demos are grouped under in the sidebar.
enum Pillar {
  foundations('Foundations'),
  multiAgent('Multi-agent'),
  durableFlutter('Durable & Flutter');

  const Pillar(this.label);
  final String label;
}

/// Metadata + builders for a single showcase demo.
class Demo {
  const Demo({
    required this.id,
    required this.title,
    required this.tagline,
    required this.pillar,
    required this.icon,
    required this.blurb,
    required this.builder,
    required this.source,
  });

  /// URL slug, e.g. `streaming-chat` → `/demos/streaming-chat`.
  final String id;

  final String title;

  /// One-line subtitle shown in the sidebar.
  final String tagline;

  final Pillar pillar;
  final IconData icon;

  /// A short paragraph shown above the live demo.
  final String blurb;

  /// Builds the live, interactive demo widget.
  final WidgetBuilder builder;

  /// The illustrative Akashi source behind the demo (shown in the Code tab).
  final String source;
}
