import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Son tam günün önceki 7 günün ortalamasına göre belirgin düşüşü.
class Drop {
  const Drop({
    required this.source,
    required this.metric,
    required this.date,
    required this.last,
    required this.base,
  });

  final String source;
  final String metric;

  /// Düşüşün görüldüğü gün (yyyy-MM-dd); bildirim günde bir kez gider.
  final String date;
  final int last;
  final double base;

  int get percent => ((1 - last / base) * 100).round();

  String get text =>
      '$source $metric dün %$percent düştü '
      '(7 gün ort. ${base.round()} → $last)';

  /// [values] eskiden yeniye tam günler. Son gün, önceki 7 günün
  /// ortalamasının [threshold] kadar altındaysa düşüş döner. Küçük sayılarda
  /// gürültü olmasın diye ortalama [minBase] altındaysa bakılmaz.
  static Drop? find(
    List<int> values, {
    required String source,
    required String metric,
    required String date,
    double threshold = 0.3,
    double minBase = 20,
  }) {
    if (values.length < 8) return null;
    final last = values.last;
    final prev = values.sublist(values.length - 8, values.length - 1);
    final base = prev.reduce((a, b) => a + b) / prev.length;
    if (base < minBase || last > base * (1 - threshold)) return null;
    return Drop(
      source: source,
      metric: metric,
      date: date,
      last: last,
      base: base,
    );
  }
}

/// macOS bildirimleri. İlk bildirimde sistem izin sorar.
class Notifier {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;
  static var _id = 0;

  static Future<void> show(String title, String body) async {
    if (!_ready) {
      await _plugin.initialize(
        settings: const InitializationSettings(
          macOS: DarwinInitializationSettings(),
        ),
      );
      _ready = true;
    }
    await _plugin.show(
      id: _id++,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        macOS: DarwinNotificationDetails(),
      ),
    );
  }
}
