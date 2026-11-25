import 'dart:convert';
import 'dart:io';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:http/http.dart' as http;

import 'store_series.dart';

/// App Store Connect satış raporlarından günlük yeni indirmeleri okur.
/// Anahtarın rolü Admin, Finance ya da Sales olmalı. Günlük rapor ertesi gün
/// (Pasifik saati) gelir.
class AppStoreClient {
  AppStoreClient({
    required String p8,
    required this.keyId,
    required this.issuerId,
    required this.vendor,
  }) : _key = ECPrivateKey(p8.trim());

  static const _api = 'https://api.appstoreconnect.apple.com';

  final ECPrivateKey _key;
  final String keyId;
  final String issuerId;
  final String vendor;
  final _http = http.Client();

  /// Geçmiş günlerin raporu değişmez; bir kez çekilen gün yeniden istenmez.
  /// Gün → (Apple kimliği → yeni indirme).
  final _cache = <String, Map<String, int>>{};

  /// Dosya adından Key ID: AuthKey_ABC123.p8 → ABC123.
  static String? keyIdFromFileName(String name) =>
      RegExp(r'AuthKey_([A-Z0-9]+)\.p8$').firstMatch(name)?.group(1);

  String _token() =>
      JWT(
        {'aud': 'appstoreconnect-v1'},
        issuer: issuerId,
        header: {'kid': keyId},
      ).sign(
        _key,
        algorithm: JWTAlgorithm.ES256,
        expiresIn: const Duration(minutes: 15),
      );

  void close() => _http.close();

  /// Hesaptaki uygulamalar: Apple kimliği, ad ve paket kimliği.
  Future<List<({String id, String name, String bundleId})>> apps() async {
    final res = await _http.get(
      Uri.parse('$_api/v1/apps?fields[apps]=name,bundleId&limit=200'),
      headers: {'authorization': 'Bearer ${_token()}'},
    );
    if (res.statusCode != 200) throw StoreException(_error(res));
    return [
      for (final a in (jsonDecode(res.body)['data'] as List))
        (
          id: a['id'] as String,
          name: (a['attributes']['name'] ?? '') as String,
          bundleId: (a['attributes']['bundleId'] ?? '') as String,
        ),
    ];
  }

  /// Son [days] günün yeni indirmeleri. [appleId] verilirse yalnız o
  /// uygulama, yoksa tüm uygulamaların toplamı.
  Future<StoreSeries> series({int days = 14, String? appleId}) async {
    final now = DateTime.now();
    final dates = [
      for (var i = 1; i <= days; i++) ymd(now.subtract(Duration(days: i))),
    ];
    final counts = await Future.wait([
      for (var i = 0; i < dates.length; i++) _day(dates[i], old: i >= 3),
    ]);
    int sum(Map<String, int> m) =>
        appleId == null ? m.values.fold(0, (a, b) => a + b) : m[appleId] ?? 0;
    return StoreSeries({
      for (var i = 0; i < dates.length; i++)
        if (counts[i] != null) dates[i]: sum(counts[i]!),
    });
  }

  /// Bir günün uygulama başına yeni indirmeleri; rapor henüz yoksa null.
  /// Eski günde rapor yoksa o gün satış yoktur: boş.
  Future<Map<String, int>?> _day(String date, {required bool old}) async {
    final cached = _cache[date];
    if (cached != null) return cached;
    final uri = Uri.parse('$_api/v1/salesReports').replace(
      queryParameters: {
        'filter[frequency]': 'DAILY',
        'filter[reportType]': 'SALES',
        'filter[reportSubType]': 'SUMMARY',
        'filter[vendorNumber]': vendor,
        'filter[version]': '1_1',
        'filter[reportDate]': date,
      },
    );
    final res = await _http.get(
      uri,
      headers: {
        'authorization': 'Bearer ${_token()}',
        'accept': 'application/a-gzip',
      },
    );
    if (res.statusCode == 404) {
      if (old) _cache[date] = const {};
      return old ? const {} : null;
    }
    if (res.statusCode != 200) throw StoreException(_error(res));

    final lines = utf8
        .decode(gzip.decode(res.bodyBytes))
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .map((l) => l.split('\t'))
        .toList();
    if (lines.isEmpty) return const {};
    final head = [for (final h in lines.first) h.trim()];
    final type = head.indexOf('Product Type Identifier');
    final units = head.indexOf('Units');
    final app = head.indexOf('Apple Identifier');
    final byApp = <String, int>{};
    for (final r in lines.skip(1)) {
      if (type < 0 || units < 0 || app < 0) continue;
      if (r.length <= units || r.length <= app) continue;
      final t = r[type].trim();
      // 1* iPhone/iPad/evrensel ilk indirme, F1 Mac uygulaması.
      if (t.startsWith('1') || t == 'F1') {
        final id = r[app].trim();
        byApp[id] = (byApp[id] ?? 0) + (int.tryParse(r[units].trim()) ?? 0);
      }
    }
    _cache[date] = byApp;
    return byApp;
  }

  /// Aktif abone sayısı (SUBSCRIPTION günlük raporu, en yeni gelen gün).
  /// [appleId] verilirse yalnız o uygulama. Rapor ya da yetki yoksa null.
  Future<int?> subscribers({String? appleId}) async {
    final now = DateTime.now();
    for (var i = 1; i <= 5; i++) {
      final uri = Uri.parse('$_api/v1/salesReports').replace(
        queryParameters: {
          'filter[frequency]': 'DAILY',
          'filter[reportType]': 'SUBSCRIPTION',
          'filter[reportSubType]': 'SUMMARY',
          'filter[vendorNumber]': vendor,
          'filter[version]': '1_3',
          'filter[reportDate]': ymd(now.subtract(Duration(days: i))),
        },
      );
      final res = await _http.get(
        uri,
        headers: {
          'authorization': 'Bearer ${_token()}',
          'accept': 'application/a-gzip',
        },
      );
      if (res.statusCode == 404) continue;
      if (res.statusCode != 200) return null;
      final lines = utf8
          .decode(gzip.decode(res.bodyBytes))
          .split('\n')
          .where((l) => l.trim().isNotEmpty)
          .map((l) => l.split('\t'))
          .toList();
      if (lines.isEmpty) return 0;
      final head = [for (final h in lines.first) h.trim()];
      final app = head.indexOf('App Apple ID');
      final active = [
        for (var c = 0; c < head.length; c++)
          if (head[c].startsWith('Active ')) c,
      ];
      var total = 0;
      for (final r in lines.skip(1)) {
        if (appleId != null && (app < 0 || r[app].trim() != appleId)) continue;
        for (final c in active) {
          if (c < r.length) total += int.tryParse(r[c].trim()) ?? 0;
        }
      }
      return total;
    }
    return null;
  }

  /// Son 30 gündeki yorumlar: [appleId] verilirse yalnız o uygulama, yoksa
  /// hepsi. Anahtarın yorumlara erişimi yoksa null.
  Future<RatingSummary?> ratings({String? appleId}) async {
    final headers = {'authorization': 'Bearer ${_token()}'};
    final List<String> ids;
    if (appleId != null) {
      ids = [appleId];
    } else {
      final apps = await _http.get(
        Uri.parse('$_api/v1/apps?fields[apps]=name&limit=200'),
        headers: headers,
      );
      if (apps.statusCode != 200) return null;
      ids = [
        for (final a in (jsonDecode(apps.body)['data'] as List))
          a['id'] as String,
      ];
    }
    final cutoff = DateTime.now().subtract(const Duration(days: 30));
    final stars = <int>[];
    final low = <Review>[];
    var allowed = false;
    for (final id in ids) {
      final res = await _http.get(
        Uri.parse(
          '$_api/v1/apps/$id/customerReviews?sort=-createdDate'
          '&limit=200&fields[customerReviews]=rating,createdDate,title,body',
        ),
        headers: headers,
      );
      if (res.statusCode != 200) continue;
      allowed = true;
      for (final r in (jsonDecode(res.body)['data'] as List)) {
        final at = r['attributes'] as Map;
        final date = DateTime.tryParse('${at['createdDate']}');
        if (date == null || date.isBefore(cutoff)) continue;
        final star = (at['rating'] as num).toInt();
        stars.add(star);
        if (Review.isLow(star, date)) {
          low.add(
            Review(
              id: 'as:${r['id']}',
              source: 'App Store',
              appId: id,
              stars: star,
              text: [
                at['title'],
                at['body'],
              ].whereType<String>().where((t) => t.isNotEmpty).join(' · '),
              at: date,
            ),
          );
        }
      }
    }
    low.sort((a, b) => b.at.compareTo(a.at));
    return allowed ? RatingSummary.of(stars, low: low) : null;
  }

  static String _error(http.Response res) {
    var detail = 'HTTP ${res.statusCode}';
    try {
      final errors = (jsonDecode(res.body) as Map)['errors'] as List;
      detail = errors.map((e) => e['detail'] ?? e['title']).join('; ');
    } catch (_) {}
    return switch (res.statusCode) {
      401 => 'App Store: anahtar, Key ID ya da Issuer ID yanlış.',
      403 => 'App Store: anahtarın rolü Admin, Finance ya da Sales olmalı.',
      _ => 'App Store: $detail',
    };
  }
}
