import '../messages/message.dart';

/// The lifecycle state of a persisted [AgentCheckpoint].
enum CheckpointStatus {
  /// A normal in-flight snapshot taken after a step executed its tools.
  running,

  /// The run is paused awaiting a human approval decision (durable HITL).
  suspended,

  /// The run finished. Reserved — the loop does not write this state yet.
  completed,
}

/// A persisted snapshot of an in-flight run, enabling resume and durable
/// human-in-the-loop pauses.
final class AgentCheckpoint {
  /// Creates a checkpoint.
  ///
  /// [pendingApproval], [resolvedResults], and [status] support durable
  /// human-in-the-loop and default to a plain `running` snapshot, so existing
  /// call sites are unaffected.
  const AgentCheckpoint({
    required this.id,
    required this.step,
    required this.messages,
    this.pendingApproval,
    this.resolvedResults = const [],
    this.status = CheckpointStatus.running,
  });

  /// A stable id for the run this snapshot belongs to.
  final String id;

  /// The step index reached.
  final int step;

  /// The conversation at this point.
  final List<Message> messages;

  /// When [status] is [CheckpointStatus.suspended], the tool call awaiting a
  /// human decision; null otherwise.
  final ToolCallPart? pendingApproval;

  /// Results for calls in the suspended step that were already resolved before
  /// the pause, so a resume does not re-run them.
  final List<ToolResultPart> resolvedResults;

  /// The checkpoint's lifecycle state.
  final CheckpointStatus status;
}

/// Persists [AgentCheckpoint]s. The in-loop seam is wired in v0.1; concrete
/// stores (e.g. SQLite via `akashi_drift`) implement durability later.
abstract interface class CheckpointStore {
  /// Persist [checkpoint].
  Future<void> save(AgentCheckpoint checkpoint);

  /// Load the latest checkpoint for run [id], or null if none.
  Future<AgentCheckpoint?> load(String id);
}

/// The simplest concrete [CheckpointStore]: an in-process map keyed by run id,
/// keeping the latest checkpoint per id. Enough to prove resume end to end and
/// to drive single-process human-in-the-loop without a database.
final class InMemoryCheckpointStore implements CheckpointStore {
  final Map<String, AgentCheckpoint> _byId = {};

  /// A read-only view of the stored checkpoints (latest per run id).
  Map<String, AgentCheckpoint> get checkpoints => Map.unmodifiable(_byId);

  @override
  Future<void> save(AgentCheckpoint checkpoint) async {
    _byId[checkpoint.id] = checkpoint;
  }

  @override
  Future<AgentCheckpoint?> load(String id) async => _byId[id];
}
