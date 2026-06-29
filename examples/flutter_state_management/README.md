# Akashi × state management

Wiring an Akashi agent into the two most common Flutter state managers,
**Riverpod** and **Bloc** — without `akashi_flutter`'s `AgentController`.

The point: the agent is plain `package:akashi` and exposes a universal
interface — `agent.stream(prompt)` (a `Stream<AgentEvent>`) and
`agent.run(prompt)` (a `Future<RunResult>`). Neither `akashi` nor
`akashi_flutter` depends on Riverpod or Bloc; a `Stream`/`Future` is the
contract every state manager already consumes. So you hold the agent's state in
*your* container and reuse `akashi_flutter`'s `MessageListView` only to render.

## Files

| File | Role |
| --- | --- |
| `lib/chat_state.dart` | Immutable `ChatState` + the framework-agnostic reducers `startUserTurn` / `foldEvent`. Shared by both recipes. |
| `lib/riverpod_example.dart` | A `Notifier` driving `agent.stream(...)`. |
| `lib/bloc_example.dart` | A `Cubit` driving `agent.stream(...)`. |
| `lib/chat_ui.dart` | `Transcript` (wraps `MessageListView`) + `Composer`, reused by both. |
| `lib/scripted_model.dart` | An offline stand-in model, so it all runs with no API key. |
| `lib/main.dart` | A launcher offering both recipes. |
| `test/recipes_test.dart` | Drives the real Cubit and Notifier and asserts the transcript folds correctly. |

The folding logic (live `TextDelta` text → in-flight bubble; each `StepFinish`
step committed to the transcript) is identical to what `AgentController` does
internally — it lives once in `foldEvent`, and the Riverpod and Bloc files differ
only in how they *store* the result.

## Run

```sh
flutter pub get
flutter test                              # behavioral validation
flutter run                               # the launcher
flutter run -t lib/riverpod_example.dart  # just the Riverpod recipe
flutter run -t lib/bloc_example.dart      # just the Bloc recipe
```

Swap `ScriptedModel()` for a real provider model (e.g. `akashi_google`'s
`GoogleProvider(apiKey: ...).languageModel('gemini-2.5-flash')`) and nothing
else changes.

## One gotcha

Riverpod and akashi both export a `Provider`. In a file that uses Riverpod's,
import akashi with `hide Provider` (see the top of `riverpod_example.dart`).
