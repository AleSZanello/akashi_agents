/// Google Gemini provider adapter for the Akashi agent framework.
///
/// Wraps `googleai_dart` behind Akashi's `LanguageModel` contract. Pair
/// [GoogleProvider] with `ToolLoopAgent` from `package:akashi/akashi.dart`.
library;

export 'src/gemini_embedding_model.dart' show GeminiEmbeddingModel;
export 'src/gemini_model.dart' show GeminiModel;
export 'src/google_provider.dart' show GoogleProvider;
