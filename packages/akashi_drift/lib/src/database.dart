import 'package:drift/drift.dart';

part 'database.g.dart';

/// One persisted checkpoint per run id (last write wins), mirroring the
/// semantics of Akashi's `InMemoryCheckpointStore`. The full checkpoint —
/// messages, pending approval, resolved results, status — is stored as a JSON
/// blob produced by `checkpointToJson`; [step] and [status] are kept as plain
/// columns for cheap querying.
class Checkpoints extends Table {
  /// The run id this snapshot belongs to (primary key).
  TextColumn get id => text()();

  /// The step index reached.
  IntColumn get step => integer()();

  /// The serialized [CheckpointStatus] name.
  TextColumn get status => text()();

  /// The serialized checkpoint (`jsonEncode(checkpointToJson(...))`).
  TextColumn get data => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// The drift database backing [Checkpoints].
@DriftDatabase(tables: [Checkpoints])
class CheckpointDatabase extends _$CheckpointDatabase {
  /// Opens the database over the given [executor].
  CheckpointDatabase(super.executor);

  @override
  int get schemaVersion => 1;
}
