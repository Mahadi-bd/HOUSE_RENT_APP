import 'dart:async';

import 'package:rent_solution/core/storage/key_value_store.dart';

/// Thrown when a remote clock is too far ahead to trust.
class HlcDriftException implements Exception {
  /// Creates the exception.
  const HlcDriftException(this.driftMs);

  /// How far ahead the remote clock is, in milliseconds.
  final int driftMs;

  @override
  String toString() => 'HlcDriftException(remote is $driftMs ms ahead)';
}

/// A hybrid logical clock value: wall time in milliseconds, a counter, and the device id.
/// Packed form sorts correctly as plain text.
class Hlc implements Comparable<Hlc> {
  /// Creates a value.
  const Hlc(this.millis, this.counter, this.nodeId);

  /// Parses [Hlc.pack] output. Throws FormatException for bad input.
  factory Hlc.parse(String packed) {
    final parts = packed.split('-');
    if (parts.length < 3) {
      throw FormatException('Not an HLC value', packed);
    }
    final millis = int.tryParse(parts[0]);
    final counter = int.tryParse(parts[1], radix: 16);
    if (millis == null || counter == null) {
      throw FormatException('Not an HLC value', packed);
    }
    return Hlc(millis, counter, parts.sublist(2).join('-'));
  }

  /// Wall-clock milliseconds since the Unix epoch (UTC).
  final int millis;

  /// Counter that orders events inside the same millisecond.
  final int counter;

  /// The device that produced this value.
  final String nodeId;

  /// Largest counter value (4 hex digits).
  static const maxCounter = 0xFFFF;

  /// Remote clocks further ahead than this are rejected.
  static const maxDriftMs = 5 * 60 * 1000;

  /// Text form: 15-digit millis, 4-digit hex counter, node id.
  String pack() =>
      '${millis.toString().padLeft(15, '0')}-${counter.toRadixString(16).padLeft(4, '0')}-$nodeId';

  @override
  int compareTo(Hlc other) {
    final byTime = millis.compareTo(other.millis);
    if (byTime != 0) {
      return byTime;
    }
    final byCounter = counter.compareTo(other.counter);
    if (byCounter != 0) {
      return byCounter;
    }
    return nodeId.compareTo(other.nodeId);
  }

  @override
  bool operator ==(Object other) =>
      other is Hlc &&
      other.millis == millis &&
      other.counter == counter &&
      other.nodeId == nodeId;

  @override
  int get hashCode => Object.hash(millis, counter, nodeId);

  @override
  String toString() => pack();
}

/// The clock of this device. Never goes backwards, even if the phone clock does.
class HlcClock {
  /// Creates a clock. [now] returns wall time in milliseconds (replace in tests).
  HlcClock(this.nodeId, {int Function()? now, Hlc? last, this.onChange})
      : _now = now ?? (() => DateTime.now().toUtc().millisecondsSinceEpoch),
        _last = last ?? Hlc(0, 0, nodeId);

  /// Called every time the clock moves (used to save it, so a restart never goes backwards).
  final void Function(Hlc value)? onChange;

  /// This device's id.
  final String nodeId;

  final int Function() _now;
  Hlc _last;

  /// The newest value issued or seen.
  Hlc get last => _last;

  /// Value for a local event or an outgoing record.
  Hlc tick() {
    final wall = _now();
    if (wall > _last.millis) {
      _last = Hlc(wall, 0, nodeId);
    } else {
      _last = _next(_last.millis, _last.counter);
    }
    onChange?.call(_last);
    return _last;
  }

  /// Merges a value received from another device and returns the new local value.
  Hlc observe(Hlc remote) {
    final wall = _now();
    if (remote.millis - wall > Hlc.maxDriftMs) {
      throw HlcDriftException(remote.millis - wall);
    }
    final top = [wall, _last.millis, remote.millis].reduce((a, b) => a > b ? a : b);
    final sameAsLast = top == _last.millis;
    final sameAsRemote = top == remote.millis;
    if (sameAsLast && sameAsRemote) {
      final higher = _last.counter > remote.counter ? _last.counter : remote.counter;
      _last = _next(top, higher);
    } else if (sameAsLast) {
      _last = _next(top, _last.counter);
    } else if (sameAsRemote) {
      _last = _next(top, remote.counter);
    } else {
      _last = Hlc(top, 0, nodeId);
    }
    onChange?.call(_last);
    return _last;
  }

  Hlc _next(int millis, int counter) {
    if (counter >= Hlc.maxCounter) {
      // Too many events in one millisecond: move to the next millisecond.
      return Hlc(millis + 1, 0, nodeId);
    }
    return Hlc(millis, counter + 1, nodeId);
  }
}

final Map<String, HlcClock> _clocksByDevice = {};

/// Loads the saved clock of [deviceId] and keeps saving it. Call once at start-up, before the
/// first write. The clock then never goes back, even after a restart or a phone clock change.
Future<void> initHlc(
  String deviceId,
  KeyValueStore store, {
  int Function()? now,
}) async {
  final key = 'hlc_last_v1_$deviceId';
  final saved = await store.read(key);
  Hlc? last;
  if (saved != null) {
    try {
      last = Hlc.parse(saved);
    } on FormatException {
      last = null;
    }
  }
  _clocksByDevice[deviceId] = HlcClock(
    deviceId,
    now: now,
    last: last,
    onChange: (value) => unawaited(store.write(key, value.pack())),
  );
}

/// Forgets all clocks (tests only).
void resetHlcForTests() => _clocksByDevice.clear();

/// Merges an HLC received from another device. Every sync applier must call this for each
/// incoming record BEFORE creating new local writes. Throws [HlcDriftException] if the remote
/// clock is too far ahead.
Hlc observeRemoteHlc(String deviceId, Hlc remote) =>
    (_clocksByDevice[deviceId] ??= HlcClock(deviceId)).observe(remote);

/// Packed HLC for a new local row on [deviceId].
String hlcNow(String deviceId) =>
    (_clocksByDevice[deviceId] ??= HlcClock(deviceId)).tick().pack();
