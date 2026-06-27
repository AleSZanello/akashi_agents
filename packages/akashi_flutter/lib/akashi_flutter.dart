/// Reactive Flutter integration for the Akashi agent framework.
///
/// Drive an agent from your widgets with [AgentController] (a `ChangeNotifier`
/// that is also the agent's `ApprovalHandler`), rebuild on its state with
/// [AgentBuilder], render a transcript with [MessageListView], and push
/// CPU-bound work to a background isolate with [offload].
library;

export 'src/agent_builder.dart';
export 'src/agent_controller.dart';
export 'src/isolate.dart';
export 'src/message_list_view.dart';
