import 'document.dart';

/// Splits a [Document] into retrievable [Chunk]s.
///
/// Implementations are pure and deterministic, so they test offline.
abstract interface class Chunker {
  /// Split [document] into chunks, in source order. A document whose text is
  /// empty or whitespace-only yields no chunks.
  List<Chunk> chunk(Document document);
}

/// Splits text to a target [chunkSize] (in characters) with [overlap], preferring
/// natural boundaries in [separators] order (paragraph → line → sentence → word)
/// before falling back to a harder cut. The sensible default.
///
/// Sizing is in **characters**, not tokens: token counting is provider-specific
/// and out of scope for v1. Pick a [chunkSize] comfortably under your embedding
/// model's token limit (a rough rule of thumb is ~4 characters per token).
final class RecursiveChunker implements Chunker {
  /// Creates a recursive chunker.
  const RecursiveChunker({
    this.chunkSize = 800,
    this.overlap = 100,
    this.separators = const ['\n\n', '\n', '. ', ' '],
  }) : assert(overlap < chunkSize, 'overlap must be smaller than chunkSize');

  /// The target maximum chunk length, in characters.
  final int chunkSize;

  /// How many characters consecutive chunks share, for context continuity.
  final int overlap;

  /// Boundary strings tried in order; earlier ones are preferred split points.
  final List<String> separators;

  @override
  List<Chunk> chunk(Document document) =>
      _chunksFromTexts(document, _split(document.text, separators));

  List<String> _split(String text, List<String> separators) {
    // Pick the first separator that occurs in [text]; fall back to the last.
    var separator = separators.isEmpty ? '' : separators.last;
    var remaining = const <String>[];
    for (var i = 0; i < separators.length; i++) {
      final candidate = separators[i];
      if (candidate.isEmpty || text.contains(candidate)) {
        separator = candidate;
        remaining = separators.sublist(i + 1);
        break;
      }
    }

    final pieces = separator.isEmpty ? text.split('') : text.split(separator);

    final chunks = <String>[];
    final good = <String>[];
    for (final piece in pieces) {
      if (piece.length < chunkSize) {
        good.add(piece);
      } else {
        if (good.isNotEmpty) {
          chunks.addAll(_merge(good, separator));
          good.clear();
        }
        // Still too big: recurse with the finer separators, or keep as-is.
        if (remaining.isEmpty) {
          chunks.add(piece);
        } else {
          chunks.addAll(_split(piece, remaining));
        }
      }
    }
    if (good.isNotEmpty) chunks.addAll(_merge(good, separator));
    return chunks;
  }

  /// Greedily packs [pieces] into chunks up to [chunkSize], re-inserting
  /// [separator] and sliding an [overlap]-sized window between them.
  List<String> _merge(List<String> pieces, String separator) {
    final separatorLen = separator.length;
    final out = <String>[];
    final current = <String>[];
    var total = 0;

    for (final piece in pieces) {
      final len = piece.length;
      if (total + len + (current.isEmpty ? 0 : separatorLen) > chunkSize &&
          current.isNotEmpty) {
        final joined = current.join(separator).trim();
        if (joined.isNotEmpty) out.add(joined);
        // Drop from the front until back under the overlap budget (or until a
        // single oversized piece is all that remains).
        while (total > overlap ||
            (total + len + (current.isEmpty ? 0 : separatorLen) > chunkSize &&
                total > 0)) {
          total -=
              current.first.length + (current.length > 1 ? separatorLen : 0);
          current.removeAt(0);
        }
      }
      current.add(piece);
      total += len + (current.length > 1 ? separatorLen : 0);
    }

    final joined = current.join(separator).trim();
    if (joined.isNotEmpty) out.add(joined);
    return out;
  }
}

/// The simplest splitter: a fixed [chunkSize] window sliding by
/// `chunkSize - overlap`, with no boundary awareness.
final class FixedSizeChunker implements Chunker {
  /// Creates a fixed-size chunker.
  const FixedSizeChunker({this.chunkSize = 800, this.overlap = 100})
      : assert(overlap < chunkSize, 'overlap must be smaller than chunkSize');

  /// The window length, in characters.
  final int chunkSize;

  /// How many characters consecutive windows share.
  final int overlap;

  @override
  List<Chunk> chunk(Document document) {
    final text = document.text;
    if (text.trim().isEmpty) return const [];
    if (text.length <= chunkSize) {
      return _chunksFromTexts(document, [text]);
    }
    final step = chunkSize - overlap;
    final windows = <String>[];
    for (var start = 0; start < text.length; start += step) {
      final end =
          start + chunkSize <= text.length ? start + chunkSize : text.length;
      windows.add(text.substring(start, end));
      if (end == text.length) break;
    }
    return _chunksFromTexts(document, windows);
  }
}

/// Builds [Chunk]s from already-split [texts], assigning the
/// `'<documentId>#<index>'` id convention and inheriting the document metadata.
List<Chunk> _chunksFromTexts(Document document, List<String> texts) => [
      for (var i = 0; i < texts.length; i++)
        Chunk(
          id: '${document.id}#$i',
          text: texts[i],
          documentId: document.id,
          metadata: document.metadata,
        ),
    ];
