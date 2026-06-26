/// Akashi — a provider-neutral agent framework for Dart & Flutter.
///
/// This is the pure-Dart core: the streaming [ToolLoopAgent], the [Agent]
/// contract, typed [Tool]s with dependency injection, the runtime [Schema]
/// builder, and sealed [Message]/[AgentEvent] unions. Pair it with a provider
/// adapter (e.g. `akashi_google`) to get a [LanguageModel].
library;

export 'src/agent/agent.dart';
export 'src/agent/approval.dart';
export 'src/agent/checkpoint.dart';
export 'src/agent/context.dart';
export 'src/agent/prepare_step.dart';
export 'src/agent/results.dart';
export 'src/agent/stop_condition.dart';
export 'src/agent/tool_loop_agent.dart';
export 'src/messages/message.dart';
export 'src/model/embedding_model.dart';
export 'src/model/language_model.dart';
export 'src/model/output.dart';
export 'src/model/usage.dart';
export 'src/observability/tracer.dart';
export 'src/schema/schema.dart';
export 'src/streaming/agent_event.dart';
export 'src/tool/tool.dart';
export 'src/transport/sse_transport.dart';
export 'src/util/cancellation.dart';
