# akashi_drift

**Durable SQLite checkpoint store** for the [Akashi](https://github.com/AleSZanello/akashi_agents)
agent framework. Implements Akashi's `CheckpointStore` over
[`drift`](https://pub.dev/packages/drift), persisting agent state so a run can
**suspend** for human-in-the-loop approval and **resume across process restarts**
— the pattern for serverless / edge, where a single run can span separate
requests or processes.

```dart
import 'dart:io';

import 'package:akashi/akashi.dart';
import 'package:akashi_drift/akashi_drift.dart';

// "Request 1": the run suspends on an approval gate, persisting to SQLite.
final store = DriftCheckpointStore.open(File('runs.sqlite'));
final agent = ToolLoopAgent(
  model: model,
  tools: tools,
  checkpoints: store,
  durableApproval: true, // persist + throw `Suspended` instead of blocking
);
try {
  await agent.run('Clean up the cache.',
      options: const RunOptions(checkpointId: 'job-42'));
} on Suspended catch (s) {
  print('awaiting approval for ${s.pendingCall.toolName}');
}
await store.close();

// "Request 2": a fresh agent reopens the same DB and resumes with the decision.
final resumed = ToolLoopAgent(
    model: model, tools: tools,
    checkpoints: DriftCheckpointStore.open(File('runs.sqlite')),
    durableApproval: true);
await resumed.run('job-42'); // ... or `resume('job-42', decision: approved())`
```

See [`example/akashi_drift_example.dart`](example/akashi_drift_example.dart) for
a complete two-process suspend → resume walkthrough on a scripted model.

## Status

v0.3. Resolves standalone (own lockfile, `akashi` path-overridden) because
`drift_dev`'s toolchain conflicts with the workspace's melos over `cli_util`.

## License

MIT.
