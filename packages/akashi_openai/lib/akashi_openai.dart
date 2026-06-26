/// OpenAI provider adapter for the Akashi agent framework.
///
/// Wraps `openai_dart` behind Akashi's `LanguageModel` and `EmbeddingModel`
/// contracts. Pair [OpenAIProvider] with `ToolLoopAgent` from
/// `package:akashi/akashi.dart`.
library;

export 'src/openai_embedding_model.dart' show OpenAIEmbeddingModel;
export 'src/openai_model.dart' show OpenAIModel;
export 'src/openai_provider.dart' show OpenAIProvider;
