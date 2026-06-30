/// A source document, before chunking.
///
/// [metadata] is opaque key/value carried through to every [Chunk] derived from
/// this document and surfaced again on each [RetrievedChunk] — use it for the
/// source name, a section, a language tag, etc. (e.g. `{'source': 'faq'}`).
final class Document {
  /// Creates a document with a stable [id] and its [text].
  const Document({
    required this.id,
    required this.text,
    this.metadata = const {},
  });

  /// A stable, caller-chosen identifier (a path, a slug, a database id).
  final String id;

  /// The full text to be chunked and embedded.
  final String text;

  /// Opaque metadata propagated to every derived [Chunk].
  final Map<String, Object?> metadata;
}

/// A retrievable slice of a [Document], plus where it came from.
final class Chunk {
  /// Creates a chunk.
  const Chunk({
    required this.id,
    required this.text,
    required this.documentId,
    this.metadata = const {},
  });

  /// The chunk's id. The built-in [Chunker]s use the convention
  /// `'<documentId>#<index>'`, which also makes [VectorStore.upsert] idempotent.
  final String id;

  /// The chunk's text.
  final String text;

  /// The id of the [Document] this chunk was split from.
  final String documentId;

  /// Metadata inherited from the source [Document].
  final Map<String, Object?> metadata;
}

/// A [Chunk] paired with its embedding vector — the unit a [VectorStore]
/// ingests.
final class EmbeddedChunk {
  /// Pairs a [chunk] with its [embedding].
  const EmbeddedChunk({required this.chunk, required this.embedding});

  /// The chunk.
  final Chunk chunk;

  /// The chunk's embedding vector.
  final List<double> embedding;
}
