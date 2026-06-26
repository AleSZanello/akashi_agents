/// Anthropic (Claude) provider adapter for the Akashi agent framework.
///
/// Wraps `anthropic_sdk_dart` behind Akashi's `LanguageModel` contract,
/// surfacing thinking blocks as reasoning (with signatures) and `tool_use`
/// blocks as tool calls. Pair [AnthropicProvider] with `ToolLoopAgent` from
/// `package:akashi/akashi.dart`.
library;

export 'src/anthropic_provider.dart' show AnthropicProvider;
export 'src/claude_model.dart' show ClaudeModel;
