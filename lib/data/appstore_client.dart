import 'dart:convert';
import 'dart:io';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:http/http.dart' as http;

import 'fx.dart';
import 'store_series.dart';

/// Bir günün satış raporu: uygulama → yeni indirme, uygulama (ya da
/// "sku:" + üst SKU) → para birimi → net gelir.
class _SalesDay {
  const _SalesDay(this.units, this.proceeds);

  static const empty = _SalesDay({}, {});

  final Map<String, int> units;
  final Map<String, Map<String, double>> proceeds;
}

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
  final _cache = <String, _SalesDay>{};

  /// Apple kimliği → SKU. Uygulama içi satın almalar raporda üst
  /// uygulamanın SKU'suyla gelir.
  Map<String, String>? _skus;

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
      Uri.parse('$_api/v1/apps?fields[apps]=name,bundleId,sku&limit=200'),
      headers: {'authorization': 'Bearer ${_token()}'},
    );
    if (res.statusCode != 200) throw StoreException(_error(res));
    final data = jsonDecode(res.body)['data'] as List;
    _skus = {
      for (final a in data)
        if (a['attributes']['sku'] is String)
          a['id'] as String: a['attributes']['sku'] as String,
    };
    return [
      for (final a in data)
        (
          id: a['id'] as String,
          name: (a['attributes']['name'] ?? '') as String,
          bundleId: (a['attributes']['bundleId'] ?? '') as String,
        ),
    ];
  }

  /// Son [days] günün yeni indirmeleri ve net geliri (USD). [appleId]
  /// verilirse yalnız o uygulama, yoksa tüm uygulamaların toplamı.
  Future<StoreSeries> series({int days = 14, String? appleId}) async {
    final now = DateTime.now();
    final dates = [
      for (var i = 1; i <= days; i++) ymd(now.subtract(Duration(days: i))),
    ];
    final reports = await Future.wait([
      for (var i = 0; i < dates.length; i++) _day(dates[i], old: i >= 3),
    ]);
    if (appleId != null && _skus == null) {
      try {
        await apps();
      } catch (_) {}
    }
    final sku = appleId == null ? null : _skus?[appleId];
    final rates = await Fx.rates();

    int units(_SalesDay d) => appleId == null
        ? d.units.values.fold(0, (a, b) => a + b)
        : d.units[appleId] ?? 0;
    double? money(_SalesDay d) {
      if (rates == null) return null;
      final sum = <String, double>{};
      for (final e in d.proceeds.entries) {
        if (appleId != null && e.key != appleId && e.key != 'sku:$sku') {
          continue;
        }
        e.value.forEach((c, v) => addMoney(sum, c, v));
      }
      return Fx.toUsd(sum, rates);
    }

    return StoreSeries(
      {
        for (var i = 0; i < dates.length; i++)
          if (reports[i] != null) dates[i]: units(reports[i]!),
      },
      revenue: {
        for (var i = 0; i < dates.length; i++)
          if (reports[i] != null) dates[i]: ?money(reports[i]!),
      },
    );
  }

  /// Bir günün uygulama başına yeni indirmeleri ve gelirleri; rapor henüz
  /// yoksa null. Eski günde rapor yoksa o gün satış yoktur: boş.
  Future<_SalesDay?> _day(String date, {required bool old}) async {
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
      if (old) _cache[date] = _SalesDay.empty;
      return old ? _SalesDay.empty : null;
    }
    if (res.statusCode != 200) throw StoreException(_error(res));

    final lines = utf8
        .decode(gzip.decode(res.bodyBytes))
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .map((l) => l.split('\t'))
        .toList();
    if (lines.isEmpty) return _SalesDay.empty;
    final head = [for (final h in lines.first) h.trim()];
    final type = head.indexOf('Product Type Identifier');
    final units = head.indexOf('Units');
    final app = head.indexOf('Apple Identifier');
    final parent = head.indexOf('Parent Identifier');
    final proceeds = head.indexOf('Developer Proceeds');
    final currency = head.indexOf('Currency of Proceeds');
    String cell(List<String> r, int i) =>
        i >= 0 && i < r.length ? r[i].trim() : '';

    final day = _SalesDay({}, {});
    if (type < 0 || units < 0 || app < 0) return day;
    for (final r in lines.skip(1)) {
      final t = cell(r, type);
      final id = cell(r, app);
      final n = int.tryParse(cell(r, units)) ?? 0;
      // 1* iPhone/iPad/evrensel ilk indirme, F1 Mac uygulaması.
      if (t.startsWith('1') || t == 'F1') {
        day.units[id] = (day.units[id] ?? 0) + n;
      }
      // Developer Proceeds birim başına; iadeler eksi adetle gelir.
      final each = double.tryParse(cell(r, proceeds)) ?? 0;
      if (each == 0 || n == 0) continue;
      final p = cell(r, parent);
      final key = p.isEmpty ? id : 'sku:$p';
      addMoney(day.proceeds.putIfAbsent(key, () => {}), cell(r, currency),
          each * n);
    }
    _cache[date] = day;
    return day;
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

  /// Ağa çıkmadan önce alanları denetler; sorun varsa ne yapılacağını
  /// söyleyen mesaj döner.
  static String? checkInput({
    required String p8,
    required String keyId,
    required String issuerId,
    required String vendor,
  }) {
    if (!p8.contains('PRIVATE KEY')) {
      return 'Seçilen dosya bir .p8 anahtarı değil. Users and Access > '
          'Integrations > App Store Connect API\'den indirilen AuthKey_….p8 '
          'dosyasını seçin.';
    }
    if (!RegExp(r'^[A-Z0-9]{10}$').hasMatch(keyId)) {
      return 'Key ID 10 karakterli olmalı (ör. 2X9R4HXF34). Anahtar listesinde '
          '"Key ID" sütununda yazar.';
    }
    if (!RegExp(
      r'^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$',
    ).hasMatch(issuerId)) {
      return 'Issuer ID bir UUID olmalı (ör. 57246542-96fe-1a63-e053-…). '
          'Integrations sayfasında anahtar listesinin üstünde yazar.';
    }
    if (!RegExp(r'^\d{6,}$').hasMatch(vendor)) {
      return 'Vendor numarası yalnız rakamlardan oluşur (ör. 85012345). '
          'Payments and Financial Reports sayfasının sol üstünde yazar.';
    }
    return null;
  }

  static String _error(http.Response res) {
    var detail = 'HTTP ${res.statusCode}';
    try {
      final errors = (jsonDecode(res.body) as Map)['errors'] as List;
      detail = errors.map((e) => e['detail'] ?? e['title']).join('; ');
    } catch (_) {}
    if (detail.toLowerCase().contains('vendor')) {
      return 'App Store: vendor numarası bu hesaba ait değil. Payments and '
          'Financial Reports sayfasının sol üstündeki numarayı girin.';
    }
    return switch (res.statusCode) {
      401 =>
        'App Store: anahtar kabul edilmedi. Key ID ve Issuer ID\'nin bu .p8 '
            'dosyasına ait olduğunu, anahtarın iptal edilmediğini kontrol edin.',
      403 =>
        'App Store: anahtarın satış raporlarını okuma yetkisi yok. Users and '
            'Access > Integrations\'da Finance (ya da Admin, Sales) rolüyle '
            'yeni bir anahtar oluşturun.',
      429 => 'App Store: çok fazla istek. Birkaç dakika sonra yeniden deneyin.',
      _ => 'App Store: $detail',
    };
  }
}
