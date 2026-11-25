import 'dart:convert';

import 'package:http/http.dart' as http;

/// Döviz kurları (1 USD karşılığı). Mağaza gelirini dolara çevirmek için
/// open.er-api.com'dan günde bir kez alınır; kişisel veri gönderilmez.
class Fx {
  static Map<String, double>? _rates;
  static DateTime? _at;

  /// Kurlar; ağ yoksa son alınan, o da yoksa null.
  static Future<Map<String, double>?> rates() async {
    final at = _at;
    if (_rates != null &&
        at != null &&
        DateTime.now().difference(at) < const Duration(hours: 12)) {
      return _rates;
    }
    try {
      final res = await http
          .get(Uri.parse('https://open.er-api.com/v6/latest/USD'))
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map;
        final map = body['rates'] as Map?;
        if (map != null) {
          _rates = {
            for (final e in map.entries)
              if (e.value is num) '${e.key}': (e.value as num).toDouble(),
          };
          _at = DateTime.now();
        }
      }
    } catch (_) {}
    return _rates;
  }

  /// [amounts] para birimi → tutar; toplamı dolar olarak. Bilinmeyen bir
  /// birim varsa null.
  static double? toUsd(Map<String, double> amounts, Map<String, double> rates) {
    var sum = 0.0;
    for (final e in amounts.entries) {
      if (e.value == 0) continue;
      if (e.key == 'USD') {
        sum += e.value;
        continue;
      }
      final r = rates[e.key];
      if (r == null || r == 0) return null;
      sum += e.value / r;
    }
    return sum;
  }
}

/// Para birimi → tutar haritalarını toplar.
void addMoney(Map<String, double> into, String currency, double amount) {
  if (currency.isEmpty || amount == 0) return;
  into[currency] = (into[currency] ?? 0) + amount;
}
