import 'package:akashi/akashi.dart';
import 'package:akashi_gateway/akashi_gateway.dart';
import 'package:test/test.dart';

enum _Mode { ok, failBeforeEmit, failAfterEmit }

class _FakeModel implements LanguageModel {
  _FakeModel(this.providerId, this.modelId, {this.mode = _Mode.ok});

  @override
  final String providerId;
  @override
  final String modelId;

  _Mode mode;
  int calls = 0;

  @override
  Stream<ModelStreamPart> stream(ModelRequest request) async* {
    calls++;
    if (mode == _Mode.failBeforeEmit) throw StateError('boom:$providerId');
    yield TextDeltaPart('from:$providerId/$modelId');
    if (mode == _Mode.failAfterEmit) throw StateError('mid:$providerId');
    yield const FinishPart(FinishReason.stop);
  }

  @override
  Future<ModelResponse> generate(ModelRequest request) async {
    calls++;
    if (mode != _Mode.ok) throw StateError('boom:$providerId');
    return ModelResponse(
      message: AssistantMessage([TextPart('from:$providerId')]),
      finishReason: FinishReason.stop,
      usage: Usage.zero,
    );
  }
}

class _FakeProvider implements Provider {
  _FakeProvider(this.id, {this.mode = _Mode.ok});

  @override
  final String id;
  final _Mode mode;
  final Map<String, _FakeModel> built = {};

  @override
  LanguageModel languageModel(String modelId) =>
      built.putIfAbsent(modelId, () => _FakeModel(id, modelId, mode: mode));
}

ModelRequest _req() => ModelRequest(messages: [UserMessage.text('hi')]);

void main() {
  group('ProviderRegistry', () {
    test('resolves "provider/model" references', () {
      final registry = ProviderRegistry({'google': _FakeProvider('google')});
      final model = registry.model('google/gemini-2.5-flash');
      expect(model.providerId, 'google');
      expect(model.modelId, 'gemini-2.5-flash');
    });

    test('splits on the first slash so model ids may contain slashes', () {
      final registry = ProviderRegistry({'vertex': _FakeProvider('vertex')});
      expect(registry.model('vertex/publishers/google/m').modelId,
          'publishers/google/m');
    });

    test('throws for an unknown provider', () {
      final registry = ProviderRegistry({'google': _FakeProvider('google')});
      expect(() => registry.model('openai/gpt-5'),
          throwsA(isA<ProviderNotFoundException>()));
    });

    test('requires a prefix unless a default provider is set', () {
      final bare = ProviderRegistry({'google': _FakeProvider('google')});
      expect(
          () => bare.model('gemini-2.5-flash'), throwsA(isA<ArgumentError>()));

      final withDefault = ProviderRegistry(
        {'google': _FakeProvider('google')},
        defaultProvider: 'google',
      );
      expect(withDefault.model('gemini-2.5-flash').modelId, 'gemini-2.5-flash');
    });
  });

  group('FallbackModel', () {
    test('rejects an empty model list', () {
      expect(() => FallbackModel([]), throwsA(isA<ArgumentError>()));
    });

    test('fails over when the primary errors before emitting', () async {
      final primary = _FakeModel('a', 'm', mode: _Mode.failBeforeEmit);
      final backup = _FakeModel('b', 'm');
      final model = FallbackModel([primary, backup]);

      final parts = await model.stream(_req()).toList();
      expect(parts.whereType<TextDeltaPart>().single.text, 'from:b/m');
      expect(primary.calls, 1);
      expect(backup.calls, 1);
    });

    test('does not fail over once output has started (mid-stream)', () async {
      final primary = _FakeModel('a', 'm', mode: _Mode.failAfterEmit);
      final backup = _FakeModel('b', 'm');
      final model = FallbackModel([primary, backup]);

      final collected = <ModelStreamPart>[];
      await expectLater(
        () async {
          await for (final part in model.stream(_req())) {
            collected.add(part);
          }
        }(),
        throwsA(isA<StateError>()),
      );
      // The partial output was delivered, but the backup was never tried.
      expect(collected.whereType<TextDeltaPart>().single.text, 'from:a/m');
      expect(backup.calls, 0);
    });

    test('honors shouldFailover (no failover) and rethrows', () async {
      final primary = _FakeModel('a', 'm', mode: _Mode.failBeforeEmit);
      final backup = _FakeModel('b', 'm');
      final model =
          FallbackModel([primary, backup], shouldFailover: (e) => false);

      expect(model.stream(_req()).toList(), throwsA(isA<StateError>()));
      expect(backup.calls, 0);
    });

    test('generate fails over too', () async {
      final primary = _FakeModel('a', 'm', mode: _Mode.failBeforeEmit);
      final backup = _FakeModel('b', 'm');
      final model = FallbackModel([primary, backup]);

      final response = await model.generate(_req());
      expect(response.message.text, 'from:b');
    });

    test('registry.fallback builds a chain from references', () async {
      final registry = ProviderRegistry({
        'a': _FakeProvider('a', mode: _Mode.failBeforeEmit),
        'b': _FakeProvider('b'),
      });
      final model = registry.fallback(['a/m1', 'b/m2']);
      final parts = await model.stream(_req()).toList();
      expect(parts.whereType<TextDeltaPart>().single.text, 'from:b/m2');
    });
  });
}
