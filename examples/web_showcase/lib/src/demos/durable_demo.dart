import 'package:akashi/akashi.dart';
import 'package:akashi_flutter/akashi_flutter.dart';
import 'package:flutter/material.dart';

import '../scripted_model.dart';
import '../theme.dart';
import 'demo.dart';

final durableDemo = Demo(
  id: 'durable-resume',
  title: 'Durable suspend / resume',
  tagline: 'Pause across a process restart',
  pillar: Pillar.durableFlutter,
  icon: Icons.bedtime_outlined,
  blurb: 'The durability pillar. With `durableApproval` and a `CheckpointStore`, '
      'an approval doesn’t block in memory — the run persists a checkpoint and '
      'throws `Suspended`, holding ZERO compute. A brand-new agent in a fresh '
      '“process” can `resume(checkpointId, decision:)` from the store and finish. '
      'The store below is an in-browser `InMemoryCheckpointStore`.',
  builder: (_) => const _DurableDemo(),
  source: _source,
);

const _jobId = 'refund-job';

enum _Phase { idle, suspended, restarted, done }

class _DurableDemo extends StatefulWidget {
  const _DurableDemo();

  @override
  State<_DurableDemo> createState() => _DurableDemoState();
}

class _DurableDemoState extends State<_DurableDemo> {
  InMemoryCheckpointStore _store = InMemoryCheckpointStore();
  late AgentController _controller = _buildController();
  _Phase _phase = _Phase.idle;
  bool _busy = false;

  AgentController _buildController() {
    final model = ScriptedModel(
      respond: (request, _) {
        final result = lastToolResult(request);
        if (result != null) {
          return Turn(
            text: result.isError
                ? 'No refund was issued — the request was denied.'
                : 'Refund complete: ${result.output}. The customer has been '
                    'emailed a confirmation. ✅',
          );
        }
        return Turn(
          reasoning: 'Issuing money needs a human sign-off — I’ll request '
              'durable approval so the run can pause safely.',
          toolCalls: [
            ToolCallSpec('issue_refund', {'orderId': '4242'}),
          ],
        );
      },
    );
    final controller = AgentController();
    controller.agent = ToolLoopAgent(
      model: model,
      tools: [_refundTool()],
      checkpoints: _store,
      durableApproval: true,
      instructions: 'Process refunds. Refunds require durable approval.',
    );
    return controller;
  }

  Tool<Object?> _refundTool() => tool<({String orderId}), Object?>(
        name: 'issue_refund',
        description: 'Issue a \$120 refund for an order.',
        inputSchema: Schema.object(
          {'orderId': Schema.string()},
          required: ['orderId'],
          fromJson: (json) => (orderId: json['orderId']! as String),
        ),
        execute: (input, ctx) async => '\$120 on order #${input.orderId}',
        needsApproval: (input, ctx) => true,
      );

  Future<void> _start() async {
    setState(() => _busy = true);
    await _controller.send(
      'Refund order #4242 (\$120).',
      options: const RunOptions(checkpointId: _jobId),
    );
    setState(() {
      _busy = false;
      _phase = _controller.isSuspended ? _Phase.suspended : _Phase.done;
    });
  }

  void _restart() {
    _controller.dispose();
    setState(() {
      _controller = _buildController(); // fresh agent, SAME store
      _phase = _Phase.restarted;
    });
  }

  Future<void> _resume({required bool approve}) async {
    setState(() => _busy = true);
    await _controller.resume(
      _jobId,
      decision: approve
          ? const ApprovalDecision.approved()
          : const ApprovalDecision.rejected('Denied by reviewer.'),
    );
    setState(() {
      _busy = false;
      _phase = _Phase.done;
    });
  }

  void _reset() {
    _controller.dispose();
    setState(() {
      _store = InMemoryCheckpointStore();
      _controller = _buildController();
      _phase = _Phase.idle;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        _StoreCard(store: _store),
        const SizedBox(height: 16),
        _PhaseNarrative(phase: _phase),
        const SizedBox(height: 16),
        AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => _ResultPanel(controller: _controller),
        ),
        const SizedBox(height: 16),
        _Actions(
          phase: _phase,
          busy: _busy,
          onStart: _start,
          onRestart: _restart,
          onApprove: () => _resume(approve: true),
          onDeny: () => _resume(approve: false),
          onReset: _reset,
        ),
      ],
    );
  }
}

class _StoreCard extends StatelessWidget {
  const _StoreCard({required this.store});
  final InMemoryCheckpointStore store;

  @override
  Widget build(BuildContext context) {
    final cp = store.checkpoints[_jobId];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0C0F16),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AkashiColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.storage_rounded,
                  size: 17, color: AkashiColors.textSecondary),
              const SizedBox(width: 8),
              const Text('CheckpointStore',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AkashiColors.textPrimary)),
              const SizedBox(width: 8),
              const Text('InMemoryCheckpointStore',
                  style: TextStyle(
                      fontFamily: 'monospace',
                      fontFamilyFallback: kMonoFontFamilyFallback,
                      fontSize: 11.5,
                      color: AkashiColors.textFaint)),
            ],
          ),
          const SizedBox(height: 12),
          if (cp == null)
            const Text('— empty —',
                style: TextStyle(color: AkashiColors.textFaint, fontSize: 13))
          else
            Row(
              children: [
                _StatusBadge(cp.status),
                const SizedBox(width: 14),
                _kv('id', cp.id),
                const SizedBox(width: 14),
                _kv('step', '${cp.step}'),
                const SizedBox(width: 14),
                if (cp.pendingApproval != null)
                  _kv('pending', cp.pendingApproval!.toolName),
              ],
            ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) => RichText(
        text: TextSpan(
          style: const TextStyle(
            fontFamily: 'monospace',
            fontFamilyFallback: kMonoFontFamilyFallback,
            fontSize: 12.5,
          ),
          children: [
            TextSpan(text: '$k: ', style: const TextStyle(color: AkashiColors.textFaint)),
            TextSpan(text: v, style: const TextStyle(color: AkashiColors.textPrimary)),
          ],
        ),
      );
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge(this.status);
  final CheckpointStatus status;

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (status) {
      CheckpointStatus.suspended => (const Color(0xFFE0B252), 'SUSPENDED'),
      CheckpointStatus.running => (AkashiColors.accent, 'RUNNING'),
      CheckpointStatus.completed => (AkashiColors.textSecondary, 'COMPLETED'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}

class _PhaseNarrative extends StatelessWidget {
  const _PhaseNarrative({required this.phase});
  final _Phase phase;

  @override
  Widget build(BuildContext context) {
    final text = switch (phase) {
      _Phase.idle =>
        'Start the job. The agent will try to issue a refund — a tool that '
            'requires approval.',
      _Phase.suspended =>
        'The run hit the approval gate, persisted a checkpoint, and threw '
            '`Suspended`. It is holding ZERO compute right now — it could stay '
            'paused for days. Now simulate the server going away.',
      _Phase.restarted =>
        'This is a brand-new `AgentController` + agent — a fresh “process”. The '
            'original is gone, but the checkpoint survived in the store. Approve '
            'or deny to `resume(checkpointId, decision:)` from it.',
      _Phase.done => 'Resumed from the persisted checkpoint and ran to '
          'completion — across a (simulated) process restart.',
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.arrow_right_alt, size: 18, color: AkashiColors.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text,
              style: const TextStyle(
                  fontSize: 13.5,
                  height: 1.5,
                  color: AkashiColors.textSecondary)),
        ),
      ],
    );
  }
}

class _ResultPanel extends StatelessWidget {
  const _ResultPanel({required this.controller});
  final AgentController controller;

  @override
  Widget build(BuildContext context) {
    final text = controller.messages
        .whereType<AssistantMessage>()
        .map((m) => m.text)
        .where((t) => t.isNotEmpty)
        .join('\n');
    if (text.isEmpty && !controller.isRunning) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AkashiColors.surfaceHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AkashiColors.border),
      ),
      child: Text(
        controller.isRunning && text.isEmpty ? 'Resuming…' : text,
        style: const TextStyle(
            color: AkashiColors.textPrimary, fontSize: 14, height: 1.5),
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({
    required this.phase,
    required this.busy,
    required this.onStart,
    required this.onRestart,
    required this.onApprove,
    required this.onDeny,
    required this.onReset,
  });

  final _Phase phase;
  final bool busy;
  final VoidCallback onStart;
  final VoidCallback onRestart;
  final VoidCallback onApprove;
  final VoidCallback onDeny;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return switch (phase) {
      _Phase.idle => FilledButton.icon(
          onPressed: busy ? null : onStart,
          icon: const Icon(Icons.play_arrow_rounded, size: 18),
          label: const Text('Start refund job'),
        ),
      _Phase.suspended => OutlinedButton.icon(
          onPressed: busy ? null : onRestart,
          icon: const Icon(Icons.restart_alt, size: 18),
          label: const Text('Simulate process restart'),
        ),
      _Phase.restarted => Row(
          children: [
            FilledButton.icon(
              onPressed: busy ? null : onApprove,
              icon: const Icon(Icons.check, size: 16),
              label: const Text('Approve & resume'),
            ),
            const SizedBox(width: 10),
            OutlinedButton.icon(
              onPressed: busy ? null : onDeny,
              icon: const Icon(Icons.close, size: 16),
              label: const Text('Deny & resume'),
            ),
          ],
        ),
      _Phase.done => OutlinedButton.icon(
          onPressed: busy ? null : onReset,
          icon: const Icon(Icons.replay, size: 18),
          label: const Text('Reset demo'),
        ),
    };
  }
}

const _source = r'''
// A durable agent: an approval persists state instead of blocking in memory.
final store = DriftCheckpointStore(...); // or InMemoryCheckpointStore()
final agent = ToolLoopAgent(
  model: model,
  tools: [issueRefund], // needsApproval: (i, c) => true
  checkpoints: store,
  durableApproval: true, // <- pause by persisting, not by blocking
);

// 1. Run. On the approval gate it persists a checkpoint and throws Suspended.
final controller = AgentController(agent: agent);
await controller.send('Refund order #4242', options: RunOptions(checkpointId: 'refund-job'));
// controller.isSuspended == true; the process can now exit.

// 2. Later — even in a different process — a fresh controller resumes from the store:
final fresh = AgentController(agent: rebuildAgentWith(store));
await fresh.resume('refund-job', decision: const ApprovalDecision.approved());
''';
