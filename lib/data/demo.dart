import 'app_state.dart';
import 'drops.dart';
import 'insights.dart';
import 'store_series.dart';

/// `--dart-define=APP_SIGNAL_DEMO=true` ile derlenince panel ağa çıkmadan
/// uydurma verilerle dolar. README ekran görüntüsü için.
const bool demoMode = bool.fromEnvironment('APP_SIGNAL_DEMO');

void fillDemo(AppState s) {
  final now = DateTime.now();
  String day(int back) {
    final d = now.subtract(Duration(days: back));
    return '${d.year}-${_two(d.month)}-${_two(d.day)}';
  }

  Map<String, int> series(List<int> counts) => {
    for (var i = 0; i < counts.length; i++)
      day(counts.length + 1 - i): counts[i],
  };

  s.selectedAppId = null;
  s.apps = const [
    AppEntry(
      id: 'com.example.puzzles',
      name: 'Demo Puzzles',
      appleId: '1',
      playPackage: 'com.example.puzzles',
      ga4PropertyId: '1',
    ),
  ];
  s.ga4Settings = const Ga4Settings(
    propertyId: '0',
    propertyName: 'demo-property',
    gameDimension: 'customEvent:game',
    durationMetric: 'userEngagementDuration',
    revenueMetric: 'totalAdRevenue',
  );
  s.ga4Data = Ga4Snapshot(
    realtime: 37,
    today: 412,
    yesterday: 538,
    newToday: 96,
    daily: const [
      402,
      431,
      455,
      418,
      470,
      512,
      498,
      476,
      521,
      549,
      530,
      561,
      538,
      412,
    ],
    games: const [
      GameRow(id: 'sudoku', users: 164, seconds: 742, revenue: 3.84),
      GameRow(id: 'word_search', users: 121, seconds: 615, revenue: 2.71),
      GameRow(id: 'solitaire', users: 88, seconds: 903, revenue: 2.25),
      GameRow(id: 'nonogram', users: 61, seconds: 534, revenue: 1.12),
      GameRow(id: 'minesweeper', users: 47, seconds: 388, revenue: 0.86),
      GameRow(id: 'tangram', users: 22, seconds: 251, revenue: 0.31),
      GameRow(id: 'crossword', users: 15, seconds: 470, revenue: 0.28),
    ],
    at: now,
    retention: const Retention(
      d1: 0.41,
      d7: 0.17,
      d30: 0.08,
      d1Users: 812,
      d7Users: 3540,
      d30Users: 9120,
    ),
  );
  s.admobData = const RevenueSummary(
    today: 11.37,
    yesterday: 18.92,
    month: 402.15,
    real: true,
  );
  Map<String, double> money(List<double> v) => {
    for (var i = 0; i < v.length; i++) day(v.length + 1 - i): v[i],
  };

  s.appStoreData = StoreSeries(
    series(const [38, 42, 35, 51, 47, 44, 39, 56, 61, 48, 52, 45, 58, 63]),
    revenue: money(const [
      21.4, 18.9, 25.2, 19.7, 23.1, 27.5, 22.0, //
      24.8, 29.3, 26.1, 31.0, 28.4, 30.2, 64.7,
    ]),
  );
  s.appStoreRating = const RatingSummary(4.6, 38);
  s.playData = StoreSeries(
    series(const [71, 66, 80, 74, 92, 85, 78, 88, 95, 81, 90, 102, 97, 89]),
    revenue: money(const [
      9.8, 11.2, 8.7, 12.4, 10.1, 9.5, 11.9, //
      12.6, 10.8, 13.4, 11.7, 14.2, 12.9, 13.5,
    ]),
  );
  s.playRating = const RatingSummary(4.4, 57);
  s.drops = [
    Drop(
      source: 'App Store',
      metric: 'gelir',
      date: day(2),
      last: 6470,
      base: 2854,
      up: true,
      money: true,
    ),
  ];
  s.insights = diagnose(s);
  s.restoring = false;
}

String _two(int n) => n.toString().padLeft(2, '0');
