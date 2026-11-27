import 'package:app_signal/data/app_state.dart';
import 'package:app_signal/data/appstore_client.dart';
import 'package:app_signal/data/drops.dart';
import 'package:app_signal/data/fx.dart';
import 'package:app_signal/data/store_series.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Drop.find', () {
    Drop? find(List<int> v, {double minBase = 20, bool money = false}) =>
        Drop.find(
          v,
          source: 'App Store',
          metric: 'kurulum',
          date: '2026-11-24',
          minBase: minBase,
          money: money,
        );

    test('sıçrama', () {
      final d = find([100, 100, 100, 100, 100, 100, 100, 250])!;
      expect(d.up, isTrue);
      expect(d.times, '2,5');
      expect(d.text, contains('uçtu'));
    });

    test('düşüş', () {
      final d = find([100, 100, 100, 100, 100, 100, 100, 60])!;
      expect(d.up, isFalse);
      expect(d.percent, 40);
    });

    test('normal gün ve az veri', () {
      expect(find([100, 100, 100, 100, 100, 100, 100, 120]), isNull);
      expect(find([100, 100, 100, 250]), isNull);
      expect(find([5, 5, 5, 5, 5, 5, 5, 50]), isNull);
    });

    test('para gizleme', () {
      final d = find(
        [3000, 3000, 3000, 3000, 3000, 3000, 3000, 9000],
        minBase: 2000,
        money: true,
      )!;
      expect(d.text, contains(r'$90.00'));
      expect(d.textFor(hideMoney: true), isNot(contains(r'$')));
    });
  });

  test('StoreSeries hafta ve gelir', () {
    final dates = [
      for (var i = 1; i <= 14; i++) '2026-11-${'$i'.padLeft(2, '0')}',
    ];
    final s = StoreSeries(
      {for (final d in dates) d: 10},
      revenue: {for (final d in dates) d: 1.5},
    );
    expect(s.week, 70);
    expect(s.prevWeek, 70);
    expect(s.weekRevenue, closeTo(10.5, 1e-9));
    expect(s.revenueCents.last, 150);
    expect(StoreSeries({'2026-11-01': 3}).hasRevenue, isFalse);
  });

  test('Fx.toUsd', () {
    expect(Fx.toUsd({'USD': 2, 'EUR': 1.8}, {'EUR': 0.9}), closeTo(4, 1e-9));
    expect(Fx.toUsd({'XYZ': 1}, {'EUR': 0.9}), isNull);
  });

  group('AppStoreClient.checkInput', () {
    const p8 = '-----BEGIN PRIVATE KEY-----\nabc\n-----END PRIVATE KEY-----';
    String? check({
      String key = p8,
      String keyId = '2X9R4HXF34',
      String issuer = '57246542-96fe-1a63-e053-0824d011072a',
      String vendor = '85012345',
    }) => AppStoreClient.checkInput(
      p8: key,
      keyId: keyId,
      issuerId: issuer,
      vendor: vendor,
    );

    test('geçerli', () => expect(check(), isNull));
    test('hatalı alanlar', () {
      expect(check(key: 'x'), contains('.p8'));
      expect(check(keyId: 'abc'), contains('Key ID'));
      expect(check(issuer: '1234'), contains('Issuer ID'));
      expect(check(vendor: 'V123'), contains('Vendor'));
    });
  });

  test('canlı first_open dakikaları kaydedilip geri okunur', () {
    final now = DateTime(2026, 11, 27, 19, 30);
    final m = now.millisecondsSinceEpoch ~/ 60000;
    final old = m - 2 * 24 * 60;
    final raw = AppState.encodeLiveMinutes({
      '123 s1': {
        m: {'ios': 2},
        m - 90: {'android': 1, 'ios': 1},
        old: {'ios': 5},
      },
      'remove 123 s1': {},
    });
    final back = AppState.decodeLiveMinutes(raw, now);
    expect(back.keys, ['123 s1']);
    expect(back['123 s1'], {
      m: {'ios': 2},
      m - 90: {'android': 1, 'ios': 1},
    });
    expect(AppState.decodeLiveMinutes('bozuk', now), isEmpty);
  });
}
