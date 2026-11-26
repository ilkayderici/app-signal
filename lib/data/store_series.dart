/// Bir mağazanın günlük kurulum sayıları ve net geliri (USD). Yalnız raporu
/// gelmiş günler tutulur; mağazalar veriyi bir iki gün gecikmeli verir.
class StoreSeries {
  StoreSeries(Map<String, int> byDate, {Map<String, double>? revenue})
    : days = (byDate.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))
          .map((e) => StoreDay(e.key, e.value, revenue?[e.key]))
          .toList(),
      revenueDays =
          (revenue?.entries.toList() ?? [])
            ..sort((a, b) => a.key.compareTo(b.key));

  /// Eskiden yeniye; tarih yyyy-MM-dd.
  final List<StoreDay> days;

  /// Gelirin bilindiği bütün günler, eskiden yeniye. Kurulum raporundan
  /// daha ileri gidebilir (Play'de satış raporu daha güncel).
  final List<MapEntry<String, double>> revenueDays;

  /// Gelirin bilindiği en son gün; yoksa null.
  StoreDay? get lastRevenue => revenueDays.isEmpty
      ? null
      : StoreDay(revenueDays.last.key, 0, revenueDays.last.value);

  StoreDay? get last => days.isEmpty ? null : days.last;

  /// Son 7 raporlu günün toplamı.
  int get week => _window(0).fold(0, (a, d) => a + d.count);

  /// Ondan önceki 7 günün toplamı; o kadar veri yoksa null.
  int? get prevWeek =>
      days.length < 14 ? null : _window(7).fold<int>(0, (a, d) => a + d.count);

  List<int> get values => [for (final d in days) d.count];

  /// Gelir okunabildi mi (rapor izni ve kur varsa).
  bool get hasRevenue => revenueDays.isNotEmpty;

  /// Son 7 günün net geliri; bilinmiyorsa null.
  double? get weekRevenue => _sum(_window(0));

  /// Bu ayın (yerel takvim) raporlanan günlerinin net geliri; bilinmiyorsa
  /// null. Seri ayın başına kadar uzanmalı.
  double? get monthRevenue {
    final now = DateTime.now();
    final prefix =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-';
    final month = revenueDays.where((e) => e.key.startsWith(prefix));
    if (revenueDays.isEmpty) return null;
    return month.fold<double>(0, (a, e) => a + e.value);
  }

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

/// Mağazanın toplam kurulumu ve en son raporlanan günün silme sayısı.
class InstallSummary {
  const InstallSummary({this.total, this.deletes, this.deletesDate, this.note});

  /// Yayından bu yana toplam kurulum; okunamazsa null.
  final int? total;

  /// [deletesDate] günü silinen kurulum; okunamazsa null.
  final int? deletes;

  /// yyyy-MM-dd.
  final String? deletesDate;

  /// Silme okunamadıysa nedeni (kartta ipucu olarak gösterilir).
  final String? note;

  InstallSummary copyWith({int? total}) => InstallSummary(
    total: total ?? this.total,
    deletes: deletes,
    deletesDate: deletesDate,
    note: note,
  );
}

/// Son 30 günde yazılan yorumların ortalama yıldızı.
class RatingSummary {
  const RatingSummary(
    this.average,
    this.count, {
    this.low = const [],
    this.total,
    this.totalCount,
  });

  factory RatingSummary.of(
    Iterable<int> stars, {
    List<Review> low = const [],
    double? total,
    int? totalCount,
  }) {
    final list = stars.toList();
    return RatingSummary(
      list.isEmpty ? null : list.reduce((a, b) => a + b) / list.length,
      list.length,
      low: low,
      total: total,
      totalCount: totalCount,
    );
  }

  final double? average;
  final int count;

  /// Mağazadaki yayından bu yana genel puan; alınamazsa null.
  final double? total;

  /// Genel puanı veren oy sayısı; mağaza vermiyorsa null (Play vermez).
  final int? totalCount;

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
