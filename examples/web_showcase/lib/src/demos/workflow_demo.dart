import 'dart:async';

import 'package:akashi/akashi.dart';
import 'package:akashi_workflow/akashi_workflow.dart';
import 'package:flutter/material.dart';

import '../scripted_model.dart';
import '../theme.dart';
import 'demo.dart';

final workflowDemo = Demo(
  id: 'workflow-pipeline',
  title: 'Workflow orchestration',
  tagline: 'Code-driven fan-out + synthesize',
  pillar: Pillar.multiAgent,
  icon: Icons.hub_outlined,
  blurb:
      'The deterministic counterpart to model-driven multi-agent. With '
      '`akashi_workflow` YOU write the topology — here: plan → fan out research '
      'agents (bounded to 2 at a time, with retries) → synthesize. Watch nodes '
      'move queued → running → done, driven by the workflow’s event stream. One '
      'task fails its first attempt to show backoff + retry.',
  builder: (_) => const _WorkflowDemo(),
  source: _source,
);

const _subtopics = ['isolates', 'event loop', 'async / await', 'streams'];
const _flakyTopic = 'event loop';

enum _Status { queued, running, retrying, done, failed }

class _Node {
  _Node(this.title);
  final String title;
  _Status status = _Status.queued;
  int attempt = 0;
}

class _WorkflowDemo extends StatefulWidget {
  const _WorkflowDemo();

  @override
  State<_WorkflowDemo> createState() => _WorkflowDemoState();
}

class _WorkflowDemoState extends State<_WorkflowDemo> {
  Workflow? _wf;
  StreamSubscription<WorkflowEvent>? _sub;

  late Map<String, _Node> _nodes;
  final List<String> _log = [];
  String _report = '';
  bool _running = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _reset();
  }

  void _reset() {
    _sub?.cancel();
    _wf?.dispose();
    _wf = null;
    _nodes = {
      for (final topic in _subtopics) 'research:$topic': _Node(topic),
      'synthesize': _Node('synthesize'),
    };
    _log.clear();
    _report = '';
    _running = false;
    _done = false;
  }

  @override
  void dispose() {
    _sub?.cancel();
    _wf?.cancelAll();
    _wf?.dispose();
    super.dispose();
  }

  void _onEvent(WorkflowEvent event) {
    final node = _nodes[event.label];
    if (node == null) return;
    setState(() {
      switch (event) {
        case TaskStarted():
          node.status = _Status.running;
          node.attempt = event.attempt;
          _log.add('▶ ${event.label} (attempt ${event.attempt})');
        case TaskSucceeded():
          node.status = _Status.done;
          _log.add('✓ ${event.label}');
        case TaskFailed():
          node.status = event.willRetry ? _Status.retrying : _Status.failed;
          _log.add('✗ ${event.label} — ${event.error}');
        case TaskRetrying():
          node.status = _Status.retrying;
          _log.add(
            '↻ retrying ${event.label} in ${event.delay.inMilliseconds}ms',
          );
      }
    });
  }

  Future<void> _run() async {
    setState(_reset);
    final wf = Workflow(maxConcurrency: 2); // only 2 researchers at once
    _wf = wf;
    _sub = wf.events.listen(_onEvent);
    setState(() => _running = true);

    final researcher = ToolLoopAgent(
      model: ScriptedModel(
        respond: (request, _) => Turn(
          text:
              'finding on “${lastUserText(request)}”: no shared memory; '
              'message passing.',
        ),
      ),
    );

    var flakyArmed = true;
    final findings = await wf.parallelSettled<String>([
      for (final topic in _subtopics)
        Task<String>(
          (ctx) async {
            if (topic == _flakyTopic && flakyArmed) {
              flakyArmed = false;
              await Future<void>.delayed(const Duration(milliseconds: 250));
              throw StateError('knowledge base timeout');
            }
            final result = await researcher.run(
              'Research $topic',
              options: RunOptions(cancel: ctx.cancel),
            );
            return '$topic — ${result.text}';
          },
          label: 'research:$topic',
          retry: const RetryPolicy(
            maxAttempts: 2,
            initialDelay: Duration(milliseconds: 600),
          ),
        ),
    ]);

    final gathered = findings.where((r) => r.ok).map((r) => r.value!).toList();

    final writer = ToolLoopAgent(
      model: ScriptedModel(
        respond: (request, _) => Turn(
          text:
              'Synthesis of ${gathered.length} findings: Dart concurrency is '
              'built on isolates (no shared memory) coordinated by the event '
              'loop, with async/await and streams as the ergonomic surface.',
        ),
      ),
    );
    final report = await wf.run(
      agentTask(
        writer,
        'Synthesize:\n${gathered.join('\n')}',
        label: 'synthesize',
      ),
    );

    if (!mounted) return;
    setState(() {
      _report = report;
      _running = false;
      _done = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        Row(
          children: [
            FilledButton.icon(
              onPressed: _running ? null : _run,
              icon: Icon(
                _done ? Icons.replay : Icons.play_arrow_rounded,
                size: 18,
              ),
              label: Text(_done ? 'Run again' : 'Run workflow'),
            ),
            const SizedBox(width: 12),
            if (_running)
              const Text(
                'orchestrating…',
                style: TextStyle(color: AkashiColors.textSecondary),
              ),
          ],
        ),
        const SizedBox(height: 18),
        _StageLabel('1 · Fan-out research', 'maxConcurrency: 2 · retry: 2'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final topic in _subtopics)
              _NodeCard(node: _nodes['research:$topic']!),
          ],
        ),
        const SizedBox(height: 18),
        _StageLabel('2 · Synthesize', 'one writer agent merges the findings'),
        const SizedBox(height: 10),
        _NodeCard(node: _nodes['synthesize']!, wide: true),
        if (_report.isNotEmpty) ...[
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AkashiColors.surfaceHigh,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AkashiColors.border),
            ),
            child: Text(
              _report,
              style: const TextStyle(
                color: AkashiColors.textPrimary,
                height: 1.5,
                fontSize: 14,
              ),
            ),
          ),
        ],
        const SizedBox(height: 18),
        _StageLabel('Event stream', 'Workflow.events'),
        const SizedBox(height: 8),
        _EventLog(lines: _log),
      ],
    );
  }
}

class _StageLabel extends StatelessWidget {
  const _StageLabel(this.title, this.subtitle);
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: AkashiColors.textPrimary,
            fontSize: 14.5,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            subtitle,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontFamilyFallback: kMonoFontFamilyFallback,
              color: AkashiColors.textFaint,
              fontSize: 11.5,
            ),
          ),
        ),
      ],
    );
  }
}

class _NodeCard extends StatelessWidget {
  const _NodeCard({required this.node, this.wide = false});
  final _Node node;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (node.status) {
      _Status.queued => (AkashiColors.textFaint, Icons.schedule),
      _Status.running => (AkashiColors.primary, Icons.autorenew),
      _Status.retrying => (const Color(0xFFE0B252), Icons.replay),
      _Status.done => (AkashiColors.accent, Icons.check_circle),
      _Status.failed => (Theme.of(context).colorScheme.error, Icons.error),
    };
    return Container(
      width: wide ? double.infinity : 200,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AkashiColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Row(
        children: [
          if (node.status == _Status.running)
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: color),
            )
          else
            Icon(icon, size: 16, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  node.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AkashiColors.textPrimary,
                    fontSize: 13.5,
                  ),
                ),
                Text(
                  node.status.name +
                      (node.attempt > 1 ? ' · attempt ${node.attempt}' : ''),
                  style: TextStyle(color: color, fontSize: 11.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EventLog extends StatelessWidget {
  const _EventLog({required this.lines});
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 150,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0C0F16),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AkashiColors.border),
      ),
      child: lines.isEmpty
          ? const Center(
              child: Text(
                'Run the workflow to see live events.',
                style: TextStyle(color: AkashiColors.textFaint, fontSize: 12),
              ),
            )
          : ListView(
              reverse: true,
              children: [
                for (final line in lines.reversed)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1),
                    child: Text(
                      line,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontFamilyFallback: kMonoFontFamilyFallback,
                        fontSize: 12,
                        color: AkashiColors.textSecondary,
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

const _source = r'''
final wf = Workflow(maxConcurrency: 2); // bound the fan-out

// 1. FAN-OUT — one researcher agent per subtopic, retried with backoff.
//    parallelSettled returns every result (successes AND failures).
final findings = await wf.parallelSettled([
  for (final topic in subtopics)
    agentTask(researcher, 'Research $topic',
        label: 'research:$topic',
        retry: const RetryPolicy(maxAttempts: 2)),
]);
final gathered = findings.where((r) => r.ok).map((r) => r.value!);

// 2. SYNTHESIZE — one writer agent merges the findings.
final report = await wf.run(
  agentTask(writer, 'Synthesize:\n${gathered.join("\n")}', label: 'synthesize'),
);

// Drive a live UI from the event stream:
wf.events.listen((e) => switch (e) {
  TaskStarted()   => markRunning(e.label),
  TaskSucceeded() => markDone(e.label),
  TaskFailed()    => markFailed(e.label, willRetry: e.willRetry),
  TaskRetrying()  => markRetrying(e.label),
});

// Also available: typed Pipeline.input<T>().stage(...).stage(...) for
// no-barrier, multi-stage flows.
''';
