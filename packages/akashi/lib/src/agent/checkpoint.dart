import '../messages/message.dart';

/// A persisted snapshot of an in-flight run, enabling resume and durable
/// human-in-the-loop pauses.
final class AgentCheckpoint {
  /// Creates a checkpoint.
  const AgentCheckpoint({
    required this.id,
    required this.step,
    required this.messages,
  });

  /// A stable id for the run this snapshot belongs to.
  final String id;

  /// The step index reached.
  final int step;

  /// The conversation at this point.
  final List<Message> messages;
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
