import 'package:flutter_test/flutter_test.dart';
import 'package:rent_solution/core/storage/key_value_store.dart';
import 'package:rent_solution/data/sync/hlc.dart';

void main() {
  setUp(resetHlcForTests);
  tearDown(resetHlcForTests);

  test('the clock is saved and a restart never goes back, even if the phone clock does', () async {
    final store = MemoryKeyValueStore();
    await initHlc('dev-a', store, now: () => 5000);
    final stamps = [for (var i = 0; i < 3; i++) Hlc.parse(hlcNow('dev-a'))];
    await Future<void>.delayed(Duration.zero);
    expect(await store.read('hlc_last_v1_dev-a'), stamps.last.pack());

    // "Restart" with a phone clock that is now far in the past.
    resetHlcForTests();
    await initHlc('dev-a', store, now: () => 10);
    final afterRestart = Hlc.parse(hlcNow('dev-a'));
    expect(afterRestart.compareTo(stamps.last), greaterThan(0));
  });

  test('a damaged saved value is ignored instead of crashing', () async {
    final store = MemoryKeyValueStore();
    await store.write('hlc_last_v1_dev-a', 'garbage');
    await initHlc('dev-a', store, now: () => 1000);
    expect(Hlc.parse(hlcNow('dev-a')).millis, 1000);
  });

  test('incoming remote clocks are merged before the next local write', () async {
    final store = MemoryKeyValueStore();
    await initHlc('dev-a', store, now: () => 1000);
    final merged = observeRemoteHlc('dev-a', const Hlc(4000, 7, 'dev-b'));
    expect(merged.millis, 4000);
    final next = Hlc.parse(hlcNow('dev-a'));
    expect(next.compareTo(const Hlc(4000, 7, 'dev-b')), greaterThan(0));
  });

  test('a remote clock far in the future is rejected', () async {
    final store = MemoryKeyValueStore();
    await initHlc('dev-a', store, now: () => 1000);
    expect(
      () => observeRemoteHlc('dev-a', Hlc(1000 + Hlc.maxDriftMs + 1, 0, 'dev-b')),
      throwsA(isA<HlcDriftException>()),
    );
  });

  test('each device keeps its own saved clock', () async {
    final store = MemoryKeyValueStore();
    await initHlc('dev-a', store, now: () => 1000);
    await initHlc('dev-b', store, now: () => 2000);
    hlcNow('dev-a');
    hlcNow('dev-b');
    await Future<void>.delayed(Duration.zero);
    expect(await store.read('hlc_last_v1_dev-a'), isNot(await store.read('hlc_last_v1_dev-b')));
  });
}
