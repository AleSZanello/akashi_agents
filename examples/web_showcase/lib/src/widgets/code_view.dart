import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// A read-only, copyable code block with a lightweight Dart-aware tint.
class CodeView extends StatefulWidget {
  const CodeView(this.code, {super.key});

  final String code;

  @override
  State<CodeView> createState() => _CodeViewState();
}

class _CodeViewState extends State<CodeView> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (!mounted) return;
    setState(() => _copied = true);
    await Future<void>.delayed(const Duration(milliseconds: 1400));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0C0F16),
        border: Border.all(color: AkashiColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AkashiColors.border),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.code, size: 16, color: AkashiColors.textFaint),
                const SizedBox(width: 8),
                const Text(
                  'Dart',
                  style: TextStyle(
                    color: AkashiColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _copy,
                  icon: Icon(
                    _copied ? Icons.check : Icons.copy,
                    size: 15,
                    color: _copied
                        ? AkashiColors.accent
                        : AkashiColors.textSecondary,
                  ),
                  label: Text(
                    _copied ? 'Copied' : 'Copy',
                    style: TextStyle(
                      color: _copied
                          ? AkashiColors.accent
                          : AkashiColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SelectableText.rich(
              _highlight(widget.code),
              style: const TextStyle(
                fontFamily: 'monospace',
                fontFamilyFallback: kMonoFontFamilyFallback,
                fontSize: 13,
                height: 1.55,
                color: Color(0xFFD6DAE6),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// A deliberately small, dependency-free Dart tinter: keywords, strings, comments,
// and types. Not a full lexer — just enough to make the snippets readable.
const _keywords = {
  'final', 'const', 'var', 'void', 'return', 'await', 'async', 'for', 'if',
  'else', 'class', 'extends', 'implements', 'true', 'false', 'null', 'new',
  'required', 'import', 'yield', 'in', 'switch', 'case', 'this', 'late',
};

// Built from a normal (escaped) string: raw strings can't hold both quote
// styles, and the string-literal rule needs to match both ' and " strings.
final _token = RegExp(
  "(//[^\\n]*)" // line comment
  "|('(?:\\\\.|[^'\\\\])*'|\"(?:\\\\.|[^\"\\\\])*\")" // single/double string
  "|(\\b[A-Z][A-Za-z0-9_]*\\b)" // Type
  "|(\\b[a-zA-Z_][a-zA-Z0-9_]*\\b)" // word
  "|(\\s+)" // whitespace
  "|(.)", // any other single char
);

TextSpan _highlight(String code) {
  final spans = <TextSpan>[];
  for (final m in _token.allMatches(code)) {
    final comment = m.group(1);
    final string = m.group(2);
    final type = m.group(3);
    final word = m.group(4);
    if (comment != null) {
      spans.add(TextSpan(text: comment, style: _style(const Color(0xFF5C6478))));
    } else if (string != null) {
      spans.add(TextSpan(text: string, style: _style(const Color(0xFF6FD08C))));
    } else if (type != null) {
      spans.add(TextSpan(text: type, style: _style(const Color(0xFF36D6C3))));
    } else if (word != null) {
      spans.add(
        _keywords.contains(word)
            ? TextSpan(text: word, style: _style(const Color(0xFFB69BFF)))
            : TextSpan(text: word),
      );
    } else {
      spans.add(TextSpan(text: m.group(0)));
    }
  }
  return TextSpan(children: spans);
}

TextStyle _style(Color color) =>
    TextStyle(color: color, fontWeight: FontWeight.w500);
