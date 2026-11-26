import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'store_series.dart';

/// AdMob Report API'den gerçek tahmini kazancı okur. AdMob servis hesabını
/// kabul etmez; uygulamaya gömülü masaüstü OAuth istemcisiyle kullanıcı
/// yalnız Google ile giriş yapar.
class AdmobClient {
  AdmobClient._(this._client, this.publisher, this.currency);

  static const _api = 'https://admob.googleapis.com/v1';
  static const _scopes = ['https://www.googleapis.com/auth/admob.readonly'];

  final AutoRefreshingAuthClient _client;

  /// "accounts/pub-123".
  final String publisher;
  final String currency;

  /// AdMob uygulama kimliği → mağaza kimliği (Apple kimliği ya da paket adı).
  Map<String, String>? _apps;

  /// Uygulamaya gömülü OAuth istemcisi (assets, git'e girmez).
  static Future<String> builtInClient() async {
    try {
      return await rootBundle.loadString('assets/admob_oauth_client.json');
    } catch (_) {
      throw const StoreException('AdMob: uygulamada OAuth istemcisi yok.');
    }
  }

  /// İndirilen OAuth istemci dosyasından kimlik. Dosya "installed" (masaüstü)
  /// ya da "web" anahtarı altında gelir.
  static ClientId clientId(String json) {
    final map = jsonDecode(json) as Map<String, dynamic>;
    final c = (map['installed'] ?? map['web']) as Map<String, dynamic>?;
    if (c == null || c['client_id'] == null || c['client_secret'] == null) {
      throw const StoreException(
        'Bu dosya bir OAuth istemcisi değil. Google Cloud > API\'ler ve '
        'Hizmetler > Kimlik bilgileri\'nden "Masaüstü uygulaması" türünde '
        'istemci oluşturup JSON\'unu indirin.',
      );
    }
    return ClientId(c['client_id'] as String, c['client_secret'] as String);
  }

  /// Tarayıcıda Google girişini açar; izin verilince yenileme jetonunu döner.
  static Future<String> signIn(
    String clientJson, {
    List<String> scopes = _scopes,
  }) async {
    final base = http.Client();
    try {
      final creds = await obtainAccessCredentialsViaUserConsent(
        clientId(clientJson),
        scopes,
        base,
        (url) => launchUrl(Uri.parse(url)),
      );
      final token = creds.refreshToken;
      if (token == null) {
        throw const StoreException('Google yenileme jetonu vermedi.');
      }
      return token;
    } finally {
      base.close();
    }
  }

  /// Kayıtlı istemci ve yenileme jetonuyla bağlanır; hesabı bulur.
  static Future<AdmobClient> connect(String clientJson, String refresh) async {
    final client = autoRefreshingClient(
      clientId(clientJson),
      AccessCredentials(
        AccessToken('Bearer', '', DateTime.utc(1970)),
        refresh,
        _scopes,
      ),
      http.Client(),
    );
    try {
      final res = await client.get(Uri.parse('$_api/accounts'));
      if (res.statusCode != 200) throw StoreException(_error(res));
      final list = (jsonDecode(res.body) as Map)['account'] as List? ?? [];
      if (list.isEmpty) {
        throw const StoreException('AdMob: bu Google hesabında AdMob yok.');
      }
      final a = list.first as Map;
      return AdmobClient._(
        client,
        a['name'] as String,
        (a['currencyCode'] ?? 'USD') as String,
      );
    } catch (e) {
      client.close();
      if (e is StoreException) rethrow;
      throw StoreException('AdMob: $e');
    }
  }

  void close() => _client.close();

  /// Bugün, dün, bu ay ve son 14 günün günlük geliri (eskiden yeniye,
  /// bugün dahil). [storeIds] verilirse (Apple kimliği / paket adı) yalnız o
  /// uygulamalar; AdMob'da eşleşen yoksa null.
  Future<({double today, double yesterday, double month, List<double> daily})?>
  earnings({Set<String>? storeIds}) async {
    List<String>? appIds;
    if (storeIds != null) {
      final apps = _apps ??= await _listApps();
      appIds = [
        for (final e in apps.entries)
          if (storeIds.contains(e.value)) e.key,
      ];
      if (appIds.isEmpty) return null;
    }
    final now = DateTime.now();
    final yday = now.subtract(const Duration(days: 1));
    // Ayın başı ya da 14 gün öncesi, hangisi daha eskiyse (grafik için).
    final monthStart = DateTime(now.year, now.month, 1);
    final twoWeeks = DateTime(now.year, now.month, now.day - 13);
    final start = monthStart.isBefore(twoWeeks) ? monthStart : twoWeeks;
    Map<String, int> date(DateTime d) => {
      'year': d.year,
      'month': d.month,
      'day': d.day,
    };
    final res = await _client.post(
      Uri.parse('$_api/$publisher/mediationReport:generate'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        'reportSpec': {
          'dateRange': {'startDate': date(start), 'endDate': date(now)},
          'dimensions': ['DATE'],
          'metrics': ['ESTIMATED_EARNINGS'],
          if (appIds != null)
            'dimensionFilters': [
              {
                'dimension': 'APP',
                'matchesAny': {'values': appIds},
              },
            ],
        },
      }),
    );
    if (res.statusCode != 200) throw StoreException(_error(res));
    final byDay = <String, double>{};
    for (final part in jsonDecode(res.body) as List) {
      final row = (part as Map)['row'] as Map?;
      if (row == null) continue;
      final day = '${row['dimensionValues']?['DATE']?['value']}';
      final micros = int.tryParse(
        '${row['metricValues']?['ESTIMATED_EARNINGS']?['microsValue']}',
      );
      byDay[day] = (byDay[day] ?? 0) + (micros ?? 0) / 1e6;
    }
    String key(DateTime d) =>
        '${d.year}${d.month.toString().padLeft(2, '0')}'
        '${d.day.toString().padLeft(2, '0')}';
    final monthKey = key(DateTime(now.year, now.month, 1));
    return (
      today: byDay[key(now)] ?? 0,
      yesterday: byDay[key(yday)] ?? 0,
      month: byDay.entries
          .where((e) => e.key.compareTo(monthKey) >= 0)
          .fold(0.0, (a, e) => a + e.value),
      daily: [
        for (var i = 13; i >= 0; i--)
          byDay[key(DateTime(now.year, now.month, now.day - i))] ?? 0,
      ],
    );
  }

  Future<Map<String, String>> _listApps() async {
    final out = <String, String>{};
    String? page;
    do {
      final res = await _client.get(
        Uri.parse('$_api/$publisher/apps')
            .replace(queryParameters: {'pageSize': '1000', 'pageToken': ?page}),
      );
      if (res.statusCode != 200) throw StoreException(_error(res));
      final body = jsonDecode(res.body) as Map;
      for (final a in (body['apps'] as List? ?? const [])) {
        final store = a['linkedAppInfo']?['appStoreId'];
        if (store is String) out[a['appId'] as String] = store;
      }
      page = body['nextPageToken'] as String?;
    } while (page != null && page.isNotEmpty);
    return out;
  }

  static String _error(http.Response res) {
    var detail = 'HTTP ${res.statusCode}';
    try {
      detail = '${(jsonDecode(res.body) as Map)['error']['message']}';
    } catch (_) {}
    return switch (res.statusCode) {
      401 => 'AdMob: giriş süresi doldu; yeniden bağlanın.',
      403 =>
        'AdMob: izin yok. Google Cloud projesinde "AdMob API" açık mı, '
            'giriş yapılan hesap AdMob hesabına ekli mi? ($detail)',
      _ => 'AdMob: $detail',
    };
  }
}
