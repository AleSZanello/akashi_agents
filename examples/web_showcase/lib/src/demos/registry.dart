import 'approval_demo.dart';
import 'demo.dart';
import 'durable_demo.dart';
import 'escalation_demo.dart';
import 'handoff_demo.dart';
import 'rag_demo.dart';
import 'state_management_demo.dart';
import 'streaming_chat_demo.dart';
import 'subagent_demo.dart';
import 'tool_calling_demo.dart';
import 'workflow_demo.dart';

/// Every demo, in sidebar order (grouped by [Pillar]).
final List<Demo> kDemos = [
  streamingChatDemo,
  toolCallingDemo,
  ragDemo,
  approvalDemo,
  subagentDemo,
  handoffDemo,
  escalationDemo,
  workflowDemo,
  durableDemo,
  stateManagementDemo,
];

/// Look up a demo by its route id, or null.
Demo? demoById(String id) {
  for (final demo in kDemos) {
    if (demo.id == id) return demo;
  }
  return null;
}
