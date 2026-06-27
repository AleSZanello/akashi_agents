/// On-device models for Akashi agents, backed by flutter_gemma.
///
/// [GemmaModel] implements `LanguageModel` over a [GemmaBackend] — proving the
/// contract is not HTTP-bound. Use [FlutterGemmaBackend] for real on-device
/// inference, or a fake backend in tests.
library;

export 'src/flutter_gemma_backend.dart';
export 'src/gemma_backend.dart';
export 'src/gemma_model.dart';
