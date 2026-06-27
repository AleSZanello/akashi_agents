import 'package:akashi_flutter/akashi_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

// Must be a top-level (or static) function to cross the isolate boundary.
int _square(int n) => n * n;

void main() {
  test('offload runs a CPU-bound callback on a background isolate', () async {
    final result = await offload(_square, 7);
    expect(result, 49);
  });
}
