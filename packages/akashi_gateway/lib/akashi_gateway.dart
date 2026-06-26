/// Model routing and provider fallback for the Akashi agent framework.
///
/// [ProviderRegistry] resolves `"provider/model"` strings; [FallbackModel]
/// chains models with transparent failover. Both sit on top of Akashi's
/// per-provider adapter packages — they route among the providers you import,
/// they don't bundle them.
library;

export 'src/fallback_model.dart';
export 'src/provider_registry.dart';
