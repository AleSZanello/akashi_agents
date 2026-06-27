import 'package:akashi/akashi.dart';
import 'package:akashi_flutter/akashi_flutter.dart';
import 'package:flutter/material.dart';

import '../theme.dart';

/// A reusable interactive chat surface over an [AgentController]: a role-aware
/// transcript (with tool-call chips, reasoning disclosures, tool results), a
/// live streaming bubble, an inline approval card (works for both in-process and
/// durable pauses), and an input row with suggestion chips.
class ChatPanel extends StatefulWidget {
  const ChatPanel({
    super.key,
    required this.controller,
    this.suggestions = const [],
    this.placeholder = 'Send a message…',
    this.emptyHint,
  });

  final AgentController controller;
  final List<String> suggestions;
  final String placeholder;
  final String? emptyHint;

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_autoScroll);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_autoScroll);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _autoScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _send([String? text]) {
    final value = (text ?? _input.text).trim();
    if (value.isEmpty) return;
    _input.clear();
    widget.controller.send(value);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return AgentBuilder(
      controller: c,
      builder: (context, controller) {
        final busy = controller.isRunning ||
            controller.pendingApproval != null ||
            controller.suspended != null;
        return Column(
          children: [
            Expanded(
              child: _Transcript(
                controller: controller,
                scroll: _scroll,
                emptyHint: widget.emptyHint,
              ),
            ),
            _ApprovalCard(controller: controller),
            if (controller.error != null)
              _ErrorBanner(error: controller.error!),
            const SizedBox(height: 8),
            if (widget.suggestions.isNotEmpty)
              _Suggestions(
                suggestions: widget.suggestions,
                enabled: !busy,
                onTap: _send,
              ),
            const SizedBox(height: 8),
            _InputRow(
              controller: _input,
              enabled: !busy,
              placeholder: widget.placeholder,
              onSend: _send,
            ),
          ],
        );
      },
    );
  }
}

class _Transcript extends StatelessWidget {
  const _Transcript({
    required this.controller,
    required this.scroll,
    this.emptyHint,
  });

  final AgentController controller;
  final ScrollController scroll;
  final String? emptyHint;

  @override
  Widget build(BuildContext context) {
    final messages =
        controller.messages.where((m) => m is! SystemMessage).toList();
    final showLive = _showLiveBubble(controller);
    final showTyping = controller.isRunning && !showLive;

    if (messages.isEmpty && !showLive && !showTyping) {
      return Center(
        child: Text(
          emptyHint ?? 'Start the conversation below.',
          style: const TextStyle(color: AkashiColors.textFaint),
        ),
      );
    }

    final children = <Widget>[
      for (final message in messages) _MessageView(message: message),
      if (showLive) _liveBubble(controller.text),
      if (showTyping) const _TypingBubble(),
    ];

    return ListView(
      controller: scroll,
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: children,
    );
  }

  static bool _showLiveBubble(AgentController c) {
    if (!c.isRunning || c.text.isEmpty) return false;
    final committed = c.messages;
    if (committed.isNotEmpty &&
        committed.last is AssistantMessage &&
        (committed.last as AssistantMessage).text == c.text) {
      return false; // already committed by the step's StepFinish
    }
    return true;
  }

  Widget _liveBubble(String text) => _Bubble(
        role: _Role.assistant,
        child: _StreamingText(text),
      );
}

enum _Role { user, assistant }

class _MessageView extends StatelessWidget {
  const _MessageView({required this.message});
  final Message message;

  @override
  Widget build(BuildContext context) {
    return switch (message) {
      UserMessage() => _Bubble(
          role: _Role.user,
          child: Text(_text(message), style: _bubbleTextStyle),
        ),
      AssistantMessage(:final content) => _Bubble(
          role: _Role.assistant,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final part in content)
                if (part is ReasoningPart)
                  _ReasoningTile(part.text)
                else if (part is TextPart && part.text.isNotEmpty)
                  Text(part.text, style: _bubbleTextStyle)
                else if (part is ToolCallPart)
                  _ToolCallChip(part),
            ],
          ),
        ),
      ToolMessage(:final content) => _Bubble(
          role: _Role.assistant,
          tinted: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final part in content)
                if (part is ToolResultPart) _ToolResultRow(part),
            ],
          ),
        ),
      SystemMessage() => const SizedBox.shrink(),
    };
  }

  static String _text(Message m) =>
      m.content.whereType<TextPart>().map((p) => p.text).join();
}

const _bubbleTextStyle = TextStyle(
  color: AkashiColors.textPrimary,
  height: 1.5,
  fontSize: 14,
);

class _Bubble extends StatelessWidget {
  const _Bubble({required this.role, required this.child, this.tinted = false});

  final _Role role;
  final Widget child;
  final bool tinted;

  @override
  Widget build(BuildContext context) {
    final isUser = role == _Role.user;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: const BoxConstraints(maxWidth: 460),
        decoration: BoxDecoration(
          color: isUser
              ? AkashiColors.primaryDim
              : (tinted ? const Color(0xFF12161F) : AkashiColors.surfaceHigh),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(isUser ? 14 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 14),
          ),
          border: Border.all(
            color: isUser ? AkashiColors.primary : AkashiColors.border,
          ),
        ),
        child: child,
      ),
    );
  }
}

class _ToolCallChip extends StatelessWidget {
  const _ToolCallChip(this.call);
  final ToolCallPart call;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF101521),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AkashiColors.primary.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.build_circle_outlined,
              size: 15, color: AkashiColors.primary),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              '${call.toolName}(${_args(call.input)})',
              style: const TextStyle(
                fontFamily: 'monospace',
                fontFamilyFallback: kMonoFontFamilyFallback,
                fontSize: 12.5,
                color: AkashiColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _args(Map<String, Object?> input) =>
      input.entries.map((e) => '${e.key}: ${e.value}').join(', ');
}

class _ToolResultRow extends StatelessWidget {
  const _ToolResultRow(this.result);
  final ToolResultPart result;

  @override
  Widget build(BuildContext context) {
    final color =
        result.isError ? Theme.of(context).colorScheme.error : AkashiColors.accent;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(result.isError ? Icons.error_outline : Icons.south_west,
              size: 14, color: color),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              '${result.toolName} → ${result.output}',
              style: TextStyle(
                fontFamily: 'monospace',
                fontFamilyFallback: kMonoFontFamilyFallback,
                fontSize: 12.5,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReasoningTile extends StatelessWidget {
  const _ReasoningTile(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        dense: true,
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 8),
        leading: const Icon(Icons.psychology_outlined,
            size: 16, color: AkashiColors.textSecondary),
        title: const Text('Reasoning',
            style: TextStyle(fontSize: 12.5, color: AkashiColors.textSecondary)),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(text,
                style: const TextStyle(
                    fontSize: 12.5,
                    color: AkashiColors.textSecondary,
                    height: 1.5)),
          ),
        ],
      ),
    );
  }
}

class _StreamingText extends StatelessWidget {
  const _StreamingText(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: _bubbleTextStyle,
        children: [
          TextSpan(text: text),
          const TextSpan(
            text: ' ▍',
            style: TextStyle(color: AkashiColors.primary),
          ),
        ],
      ),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    return const _Bubble(
      role: _Role.assistant,
      child: SizedBox(
        height: 16,
        width: 36,
        child: _Dots(),
      ),
    );
  }
}

class _Dots extends StatefulWidget {
  const _Dots();
  @override
  State<_Dots> createState() => _DotsState();
}

class _DotsState extends State<_Dots> with SingleTickerProviderStateMixin {
  late final AnimationController _ac = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ac,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final t = (_ac.value - i * 0.2) % 1.0;
            final opacity = 0.3 + 0.7 * (t < 0.5 ? t * 2 : (1 - t) * 2);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Opacity(
                opacity: opacity.clamp(0.3, 1.0),
                child: const CircleAvatar(
                    radius: 3, backgroundColor: AkashiColors.textSecondary),
              ),
            );
          }),
        );
      },
    );
  }
}

class _ApprovalCard extends StatelessWidget {
  const _ApprovalCard({required this.controller});
  final AgentController controller;

  @override
  Widget build(BuildContext context) {
    final call =
        controller.pendingApproval?.call ?? controller.suspended?.pendingCall;
    if (call == null) return const SizedBox.shrink();
    final durable = controller.suspended != null;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1A12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFB8862B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.shield_outlined,
                  size: 18, color: Color(0xFFE0B252)),
              const SizedBox(width: 8),
              Text(
                durable ? 'Durable approval required' : 'Approval required',
                style: const TextStyle(
                    fontWeight: FontWeight.w700, color: Color(0xFFE0B252)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'The agent wants to call “${call.toolName}” with '
            '${call.input}. ${durable ? 'The run was persisted and suspended.' : ''}',
            style: const TextStyle(
                color: AkashiColors.textSecondary, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              FilledButton.icon(
                onPressed: controller.approve,
                icon: const Icon(Icons.check, size: 16),
                label: const Text('Approve'),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: () => controller.reject('User denied the action.'),
                icon: const Icon(Icons.close, size: 16),
                label: const Text('Deny'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.error});
  final Object error;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.error.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: Theme.of(context).colorScheme.error.withValues(alpha: 0.5)),
      ),
      child: Text('$error',
          style: TextStyle(color: Theme.of(context).colorScheme.error)),
    );
  }
}

class _Suggestions extends StatelessWidget {
  const _Suggestions({
    required this.suggestions,
    required this.enabled,
    required this.onTap,
  });

  final List<String> suggestions;
  final bool enabled;
  final void Function(String) onTap;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final s in suggestions)
          ActionChip(
            label: Text(s, style: const TextStyle(fontSize: 12.5)),
            onPressed: enabled ? () => onTap(s) : null,
            backgroundColor: AkashiColors.surfaceHigh,
            side: const BorderSide(color: AkashiColors.border),
          ),
      ],
    );
  }
}

class _InputRow extends StatelessWidget {
  const _InputRow({
    required this.controller,
    required this.enabled,
    required this.placeholder,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool enabled;
  final String placeholder;
  final void Function([String?]) onSend;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            enabled: enabled,
            onSubmitted: enabled ? (v) => onSend(v) : null,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              hintText: placeholder,
              filled: true,
              fillColor: AkashiColors.surfaceHigh,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AkashiColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AkashiColors.primary),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AkashiColors.border),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        FilledButton(
          onPressed: enabled ? () => onSend() : null,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          ),
          child: const Icon(Icons.arrow_upward, size: 18),
        ),
      ],
    );
  }
}
