import 'package:flutter/foundation.dart';

/// Run a CPU-bound [callback] on a background isolate (Flutter's [compute]),
/// keeping the agent loop off the UI thread for heavy work such as large JSON
/// parses or on-device inference pre/post-processing.
///
/// **Deps contract — read this.** [message] and the return value must be
/// sendable across a `SendPort`. Closures and live handles (sockets, database
/// connections, plugin channels) **cannot** cross an isolate boundary.
/// Therefore:
///
/// - Construct such dependencies *inside* [callback] from a serializable config
///   passed as [message], or
/// - Offload only pure, CPU-bound stages while the agent itself stays on the
///   main isolate.
///
/// A whole agent run generally cannot be offloaded wholesale, because its tools'
/// `deps` typically hold live handles.
Future<R> offload<M, R>(
  ComputeCallback<M, R> callback,
  M message, {
  String? debugLabel,
}) => compute(callback, message, debugLabel: debugLabel ?? 'akashi.offload');
