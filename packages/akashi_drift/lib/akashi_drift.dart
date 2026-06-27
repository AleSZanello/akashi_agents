/// Durable SQLite persistence for Akashi agents.
///
/// Provides [DriftCheckpointStore], a `CheckpointStore` backed by drift +
/// SQLite, for resume and durable human-in-the-loop pauses.
library;

export 'src/database.dart' show CheckpointDatabase;
export 'src/drift_checkpoint_store.dart';
