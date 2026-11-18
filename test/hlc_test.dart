import 'package:flutter_test/flutter_test.dart';
import 'package:rent_solution/data/sync/hlc.dart';

void main() {
  test('tick moves forward with the wall clock and resets the counter', () {
    var now = 1000;
    final clock = HlcClock('dev-a', now: () => now);
    expect(clock.tick(), const Hlc(1000, 0, 'dev-a'));
    now = 2000;
    expect(clock.tick(), const Hlc(2000, 0, 'dev-a'));
  });

  test('tick inside the same millisecond raises the counter', () {
    final clock = HlcClock('dev-a', now: () => 1000);
    expect(clock.tick().counter, 0);
    expect(clock.tick().counter, 1);
    expect(clock.tick().counter, 2);
  });

  test('phone clock going backwards never makes the clock go backwards', () {
    var now = 5000;
    final clock = HlcClock('dev-a', now: () => now);
    final first = clock.tick();
    now = 1000;
    final second = clock.tick();
    expect(second.compareTo(first), greaterThan(0));
    expect(second.millis, 5000);
  });

  test('counter overflow moves to the next millisecond', () {
    final clock = HlcClock('dev-a', now: () => 1000, last: const Hlc(1000, Hlc.maxCounter, 'dev-a'));
    final next = clock.tick();
    expect(next.millis, 1001);
    expect(next.counter, 0);
  });

  test('observe merges a remote value that is ahead', () {
    final clock = HlcClock('dev-a', now: () => 1000);
    final merged = clock.observe(const Hlc(1500, 3, 'dev-b'));
    expect(merged, const Hlc(1500, 4, 'dev-a'));
    expect(clock.tick().compareTo(merged), greaterThan(0));
  });

  test('observe keeps the higher counter when both sides share the same millisecond', () {
    final clock = HlcClock('dev-a', now: () => 1000, last: const Hlc(2000, 5, 'dev-a'));
    final merged = clock.observe(const Hlc(2000, 9, 'dev-b'));
    expect(merged, const Hlc(2000, 10, 'dev-a'));
  });

  test('observe rejects a remote clock that is far in the future', () {
    final clock = HlcClock('dev-a', now: () => 1000);
    expect(
      () => clock.observe(const Hlc(1000 + Hlc.maxDriftMs + 1, 0, 'dev-b')),
      throwsA(isA<HlcDriftException>()),
    );
  });

  test('pack and parse round-trip, including node ids with dashes', () {
    const value = Hlc(1700000000123, 255, 'aaaa-bbbb-cccc');
    expect(Hlc.parse(value.pack()), value);
    expect(value.pack(), '001700000000123-00ff-aaaa-bbbb-cccc');
  });

  test('packed text sorts the same way as the values', () {
    final values = [
      const Hlc(2000, 0, 'b'),
      const Hlc(1000, 5, 'a'),
      const Hlc(1000, 6, 'a'),
      const Hlc(2000, 0, 'a'),
    ];
    final byValue = [...values]..sort();
    final byText = [...values]..sort((a, b) => a.pack().compareTo(b.pack()));
    expect(byText, byValue);
  });

  test('bad input is rejected', () {
    expect(() => Hlc.parse('nonsense'), throwsFormatException);
  });
}
