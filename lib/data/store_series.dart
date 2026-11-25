/// Bir mağazanın günlük kurulum sayıları ve net geliri (USD). Yalnız raporu
/// gelmiş günler tutulur; mağazalar veriyi bir iki gün gecikmeli verir.
class StoreSeries {
  StoreSeries(Map<String, int> byDate, {Map<String, double>? revenue})
    : days = (byDate.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))
          .map((e) => StoreDay(e.key, e.value, revenue?[e.key]))
          .toList();

  /// Eskiden yeniye; tarih yyyy-MM-dd.
  final List<StoreDay> days;

  StoreDay? get last => days.isEmpty ? null : days.last;

  /// Son 7 raporlu günün toplamı.
  int get week => _window(0).fold(0, (a, d) => a + d.count);

  /// Ondan önceki 7 günün toplamı; o kadar veri yoksa null.
  int? get prevWeek =>
      days.length < 14 ? null : _window(7).fold<int>(0, (a, d) => a + d.count);

  List<int> get values => [for (final d in days) d.count];

  /// Gelir okunabildi mi (rapor izni ve kur varsa).
  bool get hasRevenue => days.any((d) => d.revenue != null);

  /// Son 7 günün net geliri; bilinmiyorsa null.
  double? get weekRevenue => _sum(_window(0));

  double? get prevWeekRevenue => days.length < 14 ? null : _sum(_window(7));

  /// Günlük gelir, kuruş (bilinmeyen gün 0).
  List<int> get revenueCents => [
    for (final d in days) ((d.revenue ?? 0) * 100).round(),
  ];

  /// Sondan [skip] gün atlayıp önceki 7 gün.
  Iterable<StoreDay> _window(int skip) {
    final end = days.length - skip;
    if (end <= 0) return const [];
    return days.sublist(end > 7 ? end - 7 : 0, end);
  }

  static double? _sum(Iterable<StoreDay> w) {
    if (!w.any((d) => d.revenue != null)) return null;
    return w.fold<double>(0, (a, d) => a + (d.revenue ?? 0));
  }
}

class StoreDay {
  const StoreDay(this.date, this.count, [this.revenue]);

  final String date;
  final int count;

  /// Net gelir, USD; bilinmiyorsa null.
  final double? revenue;

  /// "24.11" biçimi.
  String get short => '${date.substring(8, 10)}.${date.substring(5, 7)}';
}

/// Son 30 günde yazılan yorumların ortalama yıldızı.
class RatingSummary {
  const RatingSummary(this.average, this.count, {this.low = const []});

  factory RatingSummary.of(Iterable<int> stars, {List<Review> low = const []}) {
    final list = stars.toList();
    if (list.isEmpty) return RatingSummary(null, 0, low: low);
    return RatingSummary(
      list.reduce((a, b) => a + b) / list.length,
      list.length,
      low: low,
    );
  }

  final double? average;
  final int count;

  /// Son 7 günün 1-2 yıldızlı yorumları, yeniden eskiye.
  final List<Review> low;
}

/// Tek bir mağaza yorumu.
class Review {
  const Review({
    required this.id,
    required this.source,
    required this.appId,
    required this.stars,
    required this.text,
    required this.at,
  });

  final String id;
  final String source;

  /// Apple kimliği ya da Play paket adı.
  final String appId;
  final int stars;
  final String text;
  final DateTime at;

  static bool isLow(int stars, DateTime at) =>
      stars <= 2 &&
      at.isAfter(DateTime.now().subtract(const Duration(days: 7)));
}

class StoreException implements Exception {
  const StoreException(this.message);

  final String message;

  @override
  String toString() => message;
}

String ymd(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
