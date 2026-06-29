import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'bloc_example.dart';
import 'riverpod_example.dart';

/// A launcher for the two integration recipes. Each can also be run directly
/// with `flutter run -t lib/riverpod_example.dart` (or `bloc_example.dart`).
void main() => runApp(const ExamplesApp());

class ExamplesApp extends StatelessWidget {
  const ExamplesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Akashi state-management recipes',
      home: _Home(),
    );
  }
}

class _Home extends StatelessWidget {
  const _Home();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Akashi state-management recipes')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton(
              // Riverpod needs a ProviderScope above its consumers.
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      const ProviderScope(child: RiverpodChatScreen()),
                ),
              ),
              child: const Text('Riverpod recipe'),
            ),
            const SizedBox(height: 12),
            FilledButton(
              // BlocChatScreen wraps itself in a BlocProvider.
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const BlocChatScreen()),
              ),
              child: const Text('Bloc recipe'),
            ),
          ],
        ),
      ),
    );
  }
}
