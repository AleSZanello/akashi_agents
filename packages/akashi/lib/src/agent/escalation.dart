import '../messages/message.dart';
import '../model/language_model.dart';
import 'prepare_step.dart';

/// A first-class model-escalation rule evaluated before each step.
///
/// Escalation is the cost/quality lever: start on a cheap model and switch to a
/// stronger one once the task proves hard. A policy returns the model to
/// escalate to, or null to keep the current model. Policies inspect only the
/// step index and message history (never typed deps), so they compose across
/// any `TDeps`.
///
/// Build a `prepareStep` hook from one or more policies with [escalate]:
///
/// ```dart
/// final agent = ToolLoopAgent<Deps>(
///   model: cheap,
///   prepareStep: escalate([
///     escalateOnToolErrors(to: strong, afterErrors: 2),
///     escalateAfterSteps(to: strong, afterSteps: 6),
///   ]),
/// );
/// ```
///
/// Policies take concrete [LanguageModel] instances. To escalate by a
/// `"provider/model"` reference, pre-resolve it through `akashi_gateway`'s
/// `ProviderRegistry.model(...)` and pass the result here.
abstract interface class EscalationPolicy {
  /// The model to escalate to given the [step] index and [messages] so far, or
  /// null to leave the current model in place.
  LanguageModel? escalate(int step, List<Message> messages);
}

/// Escalate to [to] once the run has accumulated at least [afterErrors] tool
/// errors. The object-API counterpart of `escalateAfterErrors`.
EscalationPolicy escalateOnToolErrors({
  required LanguageModel to,
  int afterErrors = 2,
}) =>
    _ToolErrorEscalation(to, afterErrors);

/// Escalate to [to] from step [afterSteps] onward (zero-based).
EscalationPolicy escalateAfterSteps({
  required LanguageModel to,
  required int afterSteps,
}) =>
    _StepCountEscalation(to, afterSteps);

/// Escalate to [to] once any assistant turn signals low confidence — its text
/// contains one of [phrases] (matched case-insensitively).
EscalationPolicy escalateOnLowConfidence({
  required LanguageModel to,
  List<String> phrases = const [
    "i'm not sure",
    'i am not sure',
    'cannot determine',
    "can't determine",
    'unsure',
  ],
}) =>
    _LowConfidenceEscalation(to, phrases);

/// Escalate to [to] whenever a custom [when] predicate over the step index and
/// history holds — the escape hatch for bespoke rules.
EscalationPolicy escalateWhen({
  required LanguageModel to,
  required bool Function(int step, List<Message> messages) when,
}) =>
    _PredicateEscalation(to, when);

/// Fold [policies] into a [PrepareStep] hook. Evaluated in order each step; the
/// first policy that fires swaps the step's model (so order encodes priority —
/// list cheaper-trigger tiers first). Returns no override when none fire.
PrepareStep<TDeps> escalate<TDeps>(List<EscalationPolicy> policies) {
  return (ctx) {
    for (final policy in policies) {
      final model = policy.escalate(ctx.step, ctx.messages);
      if (model != null) return StepConfig(model: model);
    }
    return null;
  };
}

int _countToolErrors(List<Message> messages) {
  var errors = 0;
  for (final message in messages) {
    if (message is ToolMessage) {
      for (final part in message.content) {
        if (part is ToolResultPart && part.isError) errors++;
      }
    }
  }
  return errors;
}

final class _ToolErrorEscalation implements EscalationPolicy {
  const _ToolErrorEscalation(this._to, this._afterErrors);

  final LanguageModel _to;
  final int _afterErrors;

  @override
  LanguageModel? escalate(int step, List<Message> messages) =>
      _countToolErrors(messages) >= _afterErrors ? _to : null;
}

final class _StepCountEscalation implements EscalationPolicy {
  const _StepCountEscalation(this._to, this._afterSteps);

  final LanguageModel _to;
  final int _afterSteps;

  @override
  LanguageModel? escalate(int step, List<Message> messages) =>
      step >= _afterSteps ? _to : null;
}

final class _LowConfidenceEscalation implements EscalationPolicy {
  _LowConfidenceEscalation(this._to, List<String> phrases)
      : _phrases = [for (final phrase in phrases) phrase.toLowerCase()];

  final LanguageModel _to;
  final List<String> _phrases;

  @override
  LanguageModel? escalate(int step, List<Message> messages) {
    for (final message in messages) {
      if (message is AssistantMessage) {
        final text = message.text.toLowerCase();
        if (_phrases.any(text.contains)) return _to;
      }
    }
    return null;
  }
}

final class _PredicateEscalation implements EscalationPolicy {
  const _PredicateEscalation(this._to, this._when);

  final LanguageModel _to;
  final bool Function(int step, List<Message> messages) _when;

  @override
  LanguageModel? escalate(int step, List<Message> messages) =>
      _when(step, messages) ? _to : null;
}
