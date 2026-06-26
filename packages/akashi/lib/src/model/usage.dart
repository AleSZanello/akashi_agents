/// Why a model stopped generating.
enum FinishReason {
  /// Natural stop (end of turn).
  stop,

  /// Hit the output token limit.
  length,

  /// Stopped to emit tool calls.
  toolCalls,

  /// Stopped by a content filter.
  contentFilter,

  /// Stopped due to an error.
  error,

  /// Provider-specific or unknown reason.
  other,
}

/// Token accounting for one or more model calls.
class Usage {
  const Usage({this.inputTokens = 0, this.outputTokens = 0});

  /// Tokens in the prompt.
  final int inputTokens;

  /// Tokens generated.
  final int outputTokens;

  /// Sum of input and output tokens.
  int get totalTokens => inputTokens + outputTokens;

  /// Combine two usages (used to accumulate across steps).
  Usage operator +(Usage other) => Usage(
        inputTokens: inputTokens + other.inputTokens,
        outputTokens: outputTokens + other.outputTokens,
      );

  /// The zero usage.
  static const Usage zero = Usage();

  @override
  String toString() =>
      'Usage(in: $inputTokens, out: $outputTokens, total: $totalTokens)';
}
