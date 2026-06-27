// A minimal reactive chat screen over an Akashi agent.
//
// Swap `ScriptedModel` for a real provider model (e.g. `akashi_google`'s
// `GeminiModel`) and the rest is unchanged. Run inside a Flutter app:
// `flutter run -t example/akashi_flutter_example.dart` from a scaffolded app.
import 'package:akashi/akashi.dart';
import 'package:akashi_flutter/akashi_flutter.dart';
import 'package:flutter/material.dart';

void main() => runApp(const ChatApp());

class ChatApp extends StatelessWidget {
  const ChatApp({super.key});

  @override
  Widget build(BuildContext context) => const MaterialApp(home: ChatScreen());
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late final AgentController<Object?> controller;
  final _input = TextEditingController();

  @override
  void initState() {
    super.initState();
    controller = AgentController<Object?>();
    final agent = ToolLoopAgent<Object?>(
      model: ScriptedModel(),
      tools: [_deleteFiles],
      approvalHandler: controller,
    );
    controller.agent = agent;
    // Bind approval requests to a dialog.
    controller.addListener(_maybePromptApproval);
  }

  Future<void> _maybePromptApproval() async {
    final pending = controller.pendingApproval;
    if (pending == null || pending.isResolved) return;
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Allow ${pending.call.toolName}?'),
        content: Text('${pending.call.input}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Deny'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Allow'),
          ),
        ],
      ),
    );
    (approved ?? false) ? controller.approve() : controller.reject('denied');
  }

  @override
  void dispose() {
    controller.removeListener(_maybePromptApproval);
    controller.dispose();
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Akashi Chat')),
      body: Column(
        children: [
          Expanded(
            child: AgentBuilder<Object?>(
              controller: controller,
              // The committed transcript, plus a live bubble for the streaming
              // assistant text of the in-flight turn.
              builder: (context, c) => Column(
                children: [
                  Expanded(
                    child: MessageListView(
                      messages: c.messages,
                      padding: const EdgeInsets.all(16),
                    ),
                  ),
                  if (c.isRunning && c.text.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(c.text),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(child: TextField(controller: _input)),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: () => controller.send(_input.text),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

final _deleteFiles = tool<({String path}), Object?>(
  name: 'delete_files',
  description: 'Permanently delete files under a path.',
  inputSchema: Schema.object(
    {'path': Schema.string()},
    required: ['path'],
    fromJson: (json) => (path: json['path']! as String),
  ),
  execute: (input, ctx) async => 'deleted ${input.path}',
  needsApproval: (input, ctx) => true,
);

/// A scripted stand-in model so the example needs no API key.
class ScriptedModel implements LanguageModel {
  @override
  String get providerId => 'scripted';

  @override
  String get modelId => 'scripted';

  @override
  Stream<ModelStreamPart> stream(ModelRequest request) async* {
    yield const TextDeltaPart('Hello from Akashi!');
    yield const FinishPart(FinishReason.stop);
  }

  @override
  Future<ModelResponse> generate(ModelRequest request) async => ModelResponse(
    message: const AssistantMessage([TextPart('Hello from Akashi!')]),
    finishReason: FinishReason.stop,
    usage: Usage.zero,
  );
}
