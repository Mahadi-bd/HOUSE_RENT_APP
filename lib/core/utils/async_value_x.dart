import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Small helper that works the same in every Riverpod version.
extension AsyncValueDataX<T> on AsyncValue<T> {
  /// The data if this value has data, otherwise null.
  T? get dataOrNull {
    final self = this;
    return self is AsyncData<T> ? self.value : null;
  }
}
