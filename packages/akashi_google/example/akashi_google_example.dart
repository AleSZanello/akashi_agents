// A tiny end-to-end example of the Gemini adapter: native structured output
// plus an embedding call.
//
// Run with: `dart run example/akashi_google_example.dart` (needs GEMINI_API_KEY).
import 'dart:io';

import 'package:akashi/akashi.dart';
import 'package:akashi_google/akashi_google.dart';

Future<void> main() async {
  final apiKey = Platform.environment['GEMINI_API_KEY'];
  if (apiKey == null) {
    stderr.writeln('Set GEMINI_API_KEY to run this example.');
    exit(64);
  }

  final provider = GoogleProvider(apiKey: apiKey);
  final agent = ToolLoopAgent<Object?>(
    model: provider.languageModel('gemini-2.5-flash'),
  );

  // Structured output — Gemini supports native JSON-Schema mode, so
  // generateObject picks it automatically (StructuredOutputCapable).
  final extracted = await agent.generateObject(
    'Extract the city and unit from: "weather in Oslo, metric".',
    schema: Output.object<({String city, String unit})>(
      {
        'city': Schema.string(),
        'unit': Output.choice(['metric', 'imperial']),
      },
      required: ['city', 'unit'],
      fromJson: (j) => (
        city: j['city']! as String,
        unit: j['unit']! as String,
      ),
    ),
  );
  print('city=${extracted.object.city} unit=${extracted.object.unit}');

  // Embeddings.
  final embedder = provider.embeddingModel('text-embedding-004')!;
  final vectors = await embedder.embed(['hello world']);
  print('embedding dimensions: ${vectors.single.length}');
}
