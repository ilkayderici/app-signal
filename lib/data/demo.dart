import 'app_state.dart';
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
  s.appStoreData = StoreSeries(
    series(const [38, 42, 35, 51, 47, 44, 39, 56, 61, 48, 52, 45, 58, 63]),
  );
  s.appStoreRating = const RatingSummary(4.6, 38);
  s.playData = StoreSeries(
    series(const [71, 66, 80, 74, 92, 85, 78, 88, 95, 81, 90, 102, 97, 89]),
  );
  s.playRating = const RatingSummary(4.4, 57);
  s.restoring = false;
}

String _two(int n) => n.toString().padLeft(2, '0');
