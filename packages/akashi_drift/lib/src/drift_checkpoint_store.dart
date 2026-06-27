import 'dart:convert';
import 'dart:io';

import 'package:akashi/akashi.dart';
import 'package:drift/native.dart';

import 'database.dart';

/// A durable [CheckpointStore] backed by SQLite via drift.
///
/// Persists each [AgentCheckpoint] (serialized with `checkpointToJson`) so a
/// run can survive process restarts and pause indefinitely — without holding
/// compute — while awaiting a durable human-in-the-loop approval. Pair it with
/// `ToolLoopAgent(durableApproval: true)`:
///
/// ```dart
/// final store = DriftCheckpointStore.open(File('runs.sqlite'));
/// final agent = ToolLoopAgent(
///   model: model, tools: tools, checkpoints: store, durableApproval: true);
/// try {
///   await agent.run(prompt, options: RunOptions(checkpointId: 'job-42'));
/// } on Suspended catch (s) {
///   // later, in another process:
///   await agent.resume(s.checkpointId, decision: ApprovalDecision.approved());
/// }
/// ```
class DriftCheckpointStore implements CheckpointStore {
  /// Wraps an existing [CheckpointDatabase].
  DriftCheckpointStore(this.database);

  /// An ephemeral, in-memory store — ideal for tests.
  factory DriftCheckpointStore.memory() =>
      DriftCheckpointStore(CheckpointDatabase(NativeDatabase.memory()));

  /// A file-backed store persisting to [file].
  factory DriftCheckpointStore.open(File file) =>
      DriftCheckpointStore(CheckpointDatabase(NativeDatabase(file)));

  /// The underlying drift database.
  final CheckpointDatabase database;

  @override
  Future<void> save(AgentCheckpoint checkpoint) async {
    final row = CheckpointsCompanion.insert(
      id: checkpoint.id,
      step: checkpoint.step,
      status: checkpoint.status.name,
      data: jsonEncode(checkpointToJson(checkpoint)),
    );
    await database.into(database.checkpoints).insertOnConflictUpdate(row);
  }

  @override
  Future<AgentCheckpoint?> load(String id) async {
    final query = database.select(database.checkpoints)
      ..where((t) => t.id.equals(id));
    final row = await query.getSingleOrNull();
    if (row == null) return null;
    return checkpointFromJson(
      (jsonDecode(row.data) as Map).cast<String, Object?>(),
    );
  }

  /// Close the underlying database.
  Future<void> close() => database.close();
}
