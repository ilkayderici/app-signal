import 'dart:convert';
import 'dart:io';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:flutter/foundation.dart';
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
  Future<_SalesDay?> _day(String date, {required bool old}) =>
      _sales('DAILY', date, old: old);

  /// [frequency] DAILY (yyyy-MM-dd), MONTHLY (yyyy-MM) ya da YEARLY (yyyy)
  /// satış raporu. Rapor yoksa [old] ise boş, değilse null.
  Future<_SalesDay?> _sales(
    String frequency,
    String date, {
    required bool old,
  }) async {
    final cacheKey = frequency == 'DAILY' ? date : '$frequency:$date';
    final cached = _cache[cacheKey];
    if (cached != null) return cached;
    final uri = Uri.parse('$_api/v1/salesReports').replace(
      queryParameters: {
        'filter[frequency]': frequency,
        'filter[reportType]': 'SALES',
        'filter[reportSubType]': 'SUMMARY',
        'filter[vendorNumber]': vendor,
        // Yıllık ve aylık özetin son sürümü 1_0.
        'filter[version]': frequency == 'DAILY' ? '1_1' : '1_0',
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
    // 404: o dönemde satış yok ya da rapor henüz hazır değil. Saklama süresi
    // dolmuş rapor da (aylık 12 ay, günlük 365 gün) eski sayılır.
    final expired =
        res.statusCode != 200 && res.body.contains('no longer available');
    if (res.statusCode == 404 || expired) {
      if (old || expired) _cache[cacheKey] = _SalesDay.empty;
      return old || expired ? _SalesDay.empty : null;
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
      addMoney(
        day.proceeds.putIfAbsent(key, () => {}),
        cell(r, currency),
        each * n,
      );
    }
    _cache[cacheKey] = day;
    return day;
  }

  /// Yayından bu yana ilk indirmeler: geçmiş yılların YEARLY, bu yılın
  /// geçmiş aylarının MONTHLY, bu ayın DAILY raporları toplanır. Henüz
  /// yayınlanmamış yıllık/aylık rapor yerine bir alt sıklık kullanılır.
  /// Apple'ın sakladığından eski yıllar sayılamaz.
  Future<int> totalInstalls({String? appleId}) async {
    final now = DateTime.now();
    int units(_SalesDay? d) => d == null
        ? 0
        : appleId == null
        ? d.units.values.fold(0, (a, b) => a + b)
        : d.units[appleId] ?? 0;
    String two(int n) => n.toString().padLeft(2, '0');

    Future<int> monthTotal(int y, int m, {required bool fallback}) async {
      final r = await _sales('MONTHLY', '$y-${two(m)}', old: !fallback);
      if (r != null) return units(r);
      // Aylık rapor henüz yok: ayın günleri tek tek.
      final last = DateTime(y, m + 1, 0).day;
      final days = await Future.wait([
        for (var d = 1; d <= last; d++)
          _sales('DAILY', '$y-${two(m)}-${two(d)}', old: true),
      ]);
      return days.fold<int>(0, (a, d) => a + units(d));
    }

    var total = 0;
    // Geçmiş yıllar: geriye doğru, rapor bulunmayan ilk yılda durulur.
    for (var y = now.year - 1; y >= now.year - 15; y--) {
      // Geçen yılın raporu yalnız ocakta henüz yayınlanmamış olabilir; başka
      // zaman 404 o yıl satış olmadığı demektir.
      final r = await _sales(
        'YEARLY',
        '$y',
        old: y < now.year - 1 || now.month > 1,
      );
      if (r == null) {
        // Geçen yılın yıllık raporu henüz yok: aylarından.
        final months = await Future.wait([
          for (var m = 1; m <= 12; m++) monthTotal(y, m, fallback: m == 12),
        ]);
        total += months.fold(0, (a, b) => a + b);
        continue;
      }
      if (r.units.isEmpty) break;
      total += units(r);
    }
    final months = await Future.wait([
      for (var m = 1; m < now.month; m++)
        monthTotal(now.year, m, fallback: m == now.month - 1),
    ]);
    total += months.fold(0, (a, b) => a + b);
    final days = await Future.wait([
      for (var d = 1; d < now.day; d++)
        _sales(
          'DAILY',
          '${now.year}-${two(now.month)}-${two(d)}',
          old: now.day - d > 3,
        ),
    ]);
    total += days.fold<int>(0, (a, d) => a + units(d));
    return total;
  }

  /// Analytics Reports API'deki ONGOING rapor isteği kimlikleri (uygulama →
  /// istek) ve indirilmiş rapor örneklerinin günlük silmeleri.
  final _requests = <String, String>{};
  final _instances = <String, Map<String, int>>{};

  /// En son raporlanan günün silmeleri ("App Store Installation and
  /// Deletion" raporu). İstek yoksa açılır; Apple ilk veriyi bir iki gün
  /// sonra üretir. Anahtarın Admin rolü yoksa ya da veri henüz yoksa
  /// silme boş, [InstallSummary.note] nedenini söyler.
  Future<InstallSummary> deletions({String? appleId}) async {
    try {
      final ids = appleId != null
          ? [appleId]
          : [for (final a in await apps()) a.id];
      final byDate = <String, int>{};
      var pending = false;
      for (final id in ids) {
        final days = await _appDeletions(id);
        if (days == null) {
          pending = true;
          continue;
        }
        days.forEach((d, n) => byDate[d] = (byDate[d] ?? 0) + n);
      }
      if (byDate.isEmpty) {
        return InstallSummary(
          note: pending
              ? 'Apple silme raporunu hazırlıyor; ilk veri bir iki gün '
                    'içinde gelir.'
              : 'Apple silme raporunda veri yok.',
        );
      }
      final last = (byDate.keys.toList()..sort()).last;
      return InstallSummary(deletes: byDate[last], deletesDate: last);
    } on StoreException catch (e) {
      return InstallSummary(note: e.message);
    }
  }

  /// Bir uygulamanın günlük silmeleri (yyyy-MM-dd → adet), en son rapor
  /// örneğinden. Rapor henüz üretilmediyse null.
  Future<Map<String, int>?> _appDeletions(String appId) async {
    final requestId = _requests[appId] ??= await _reportRequest(appId);
    final reports = await _getJson(
      '/v1/analyticsReportRequests/$requestId/reports'
      '?filter[category]=APP_USAGE&limit=200',
    );
    String? reportId;
    for (final r in reports['data'] as List) {
      final name = '${r['attributes']?['name']}';
      if (name.contains('Installation and Deletion') &&
          name.contains('Standard')) {
        reportId = r['id'] as String;
      }
    }
    if (reportId == null) return null;
    final instances = await _getJson(
      '/v1/analyticsReports/$reportId/instances'
      '?filter[granularity]=DAILY&limit=200',
    );
    final list = [
      for (final i in instances['data'] as List)
        (
          id: i['id'] as String,
          date: '${i['attributes']?['processingDate'] ?? ''}',
        ),
    ]..sort((a, b) => a.date.compareTo(b.date));
    if (list.isEmpty) return null;
    final latest = list.last;
    final cached = _instances[latest.id];
    if (cached != null) return cached;

    final segments = await _getJson(
      '/v1/analyticsReportInstances/${latest.id}/segments',
    );
    final out = <String, int>{};
    for (final s in segments['data'] as List) {
      final url = s['attributes']?['url'] as String?;
      if (url == null) continue;
      final res = await _http.get(Uri.parse(url));
      if (res.statusCode != 200) {
        throw StoreException(
          'App Store: silme raporu indirilemedi '
          '(HTTP ${res.statusCode}).',
        );
      }
      var bytes = res.bodyBytes as List<int>;
      if (bytes.length > 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) {
        bytes = gzip.decode(bytes);
      }
      _sumDeletes(utf8.decode(bytes, allowMalformed: true), appId, out);
    }
    _instances[latest.id] = out;
    return out;
  }

  /// Rapor satırlarından `Event` = Delete olanların `Counts` toplamı, güne
  /// göre. Sütun adları büyük/küçük harf duyarsız aranır.
  static void _sumDeletes(String text, String appId, Map<String, int> out) {
    final lines = text.split('\n').where((l) => l.trim().isNotEmpty).toList();
    if (lines.isEmpty) return;
    final sep = lines.first.contains('\t') ? '\t' : ',';
    List<String> split(String l) => [
      for (final c in l.split(sep)) c.trim().replaceAll('"', ''),
    ];
    final head = [for (final h in split(lines.first)) h.toLowerCase()];
    final date = head.indexOf('date');
    final event = head.indexOf('event');
    final counts = head.indexOf('counts');
    final app = head.indexOf('app apple identifier');
    if (date < 0 || event < 0 || counts < 0) {
      if (kDebugMode) debugPrint('Apple silme sütunları: $head');
      return;
    }
    for (final l in lines.skip(1)) {
      final r = split(l);
      if (r.length <= counts || r.length <= event || r.length <= date) continue;
      if (app >= 0 && app < r.length && r[app] != appId) continue;
      if (r[event].toLowerCase() != 'delete') continue;
      out[r[date]] = (out[r[date]] ?? 0) + (int.tryParse(r[counts]) ?? 0);
    }
  }

  /// Uygulamanın ONGOING rapor isteği; yoksa açılır.
  Future<String> _reportRequest(String appId) async {
    final existing = await _getJson(
      '/v1/apps/$appId/analyticsReportRequests'
      '?filter[accessType]=ONGOING',
    );
    for (final r in existing['data'] as List) {
      if (r['attributes']?['stoppedDueToInactivity'] != true) {
        return r['id'] as String;
      }
    }
    final res = await _http.post(
      Uri.parse('$_api/v1/analyticsReportRequests'),
      headers: {
        'authorization': 'Bearer ${_token()}',
        'content-type': 'application/json',
      },
      body: jsonEncode({
        'data': {
          'type': 'analyticsReportRequests',
          'attributes': {'accessType': 'ONGOING'},
          'relationships': {
            'app': {
              'data': {'type': 'apps', 'id': appId},
            },
          },
        },
      }),
    );
    if (res.statusCode != 201) throw StoreException(_analyticsError(res));
    return (jsonDecode(res.body)['data'] as Map)['id'] as String;
  }

  Future<Map<String, dynamic>> _getJson(String path) async {
    final res = await _http.get(
      Uri.parse('$_api$path'),
      headers: {'authorization': 'Bearer ${_token()}'},
    );
    if (res.statusCode != 200) throw StoreException(_analyticsError(res));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static String _analyticsError(http.Response res) => res.statusCode == 403
      ? 'App Store: anahtar Analytics raporlarını okuyamıyor. Silme sayısı '
            'için Users and Access > Integrations\'da Admin rolüyle bir anahtar '
            'gerekir.'
      : _error(res);

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
    if (!allowed) return null;
    final total = ids.length == 1 ? await _totalRating(ids.single) : null;
    return RatingSummary.of(
      stars,
      low: low,
      total: total?.$1,
      totalCount: total?.$2,
    );
  }

  /// App Store vitrinleri (iTunes lookup ülke kodları).
  static const _storefronts = [
    'ae', 'ag', 'ai', 'al', 'am', 'ao', 'ar', 'at', 'au', 'az', 'ba', 'bb', //
    'be', 'bf', 'bg', 'bh', 'bj', 'bm', 'bn', 'bo', 'br', 'bs', 'bt', 'bw',
    'by', 'bz', 'ca', 'cd', 'cg', 'ch', 'ci', 'cl', 'cm', 'cn', 'co', 'cr',
    'cv', 'cy', 'cz', 'de', 'dk', 'dm', 'do', 'dz', 'ec', 'ee', 'eg', 'es',
    'fi', 'fj', 'fm', 'fr', 'ga', 'gb', 'gd', 'ge', 'gh', 'gm', 'gr', 'gt',
    'gw', 'gy', 'hk', 'hn', 'hr', 'hu', 'id', 'ie', 'il', 'in', 'iq', 'is',
    'it', 'jm', 'jo', 'jp', 'ke', 'kg', 'kh', 'kn', 'kr', 'kw', 'ky', 'kz',
    'la', 'lb', 'lc', 'lk', 'lr', 'lt', 'lu', 'lv', 'ly', 'ma', 'md', 'me',
    'mg', 'mk', 'ml', 'mm', 'mn', 'mo', 'mr', 'ms', 'mt', 'mu', 'mv', 'mw',
    'mx', 'my', 'mz', 'na', 'ne', 'ng', 'ni', 'nl', 'no', 'np', 'nr', 'nz',
    'om', 'pa', 'pe', 'pg', 'ph', 'pk', 'pl', 'pt', 'pw', 'py', 'qa', 'ro',
    'rs', 'ru', 'rw', 'sa', 'sb', 'sc', 'se', 'sg', 'si', 'sk', 'sl', 'sn',
    'sr', 'st', 'sv', 'sz', 'tc', 'td', 'th', 'tj', 'tm', 'tn', 'to', 'tr',
    'tt', 'tw', 'tz', 'ua', 'ug', 'us', 'uy', 'uz', 'vc', 've', 'vg', 'vn',
    'vu', 'xk', 'ye', 'za', 'zm', 'zw',
  ];

  /// Uygulama → (genel puan, oy sayısı, alındığı an). Puan yavaş değişir;
  /// 175 vitrini her saat sormamak için 6 saat tutulur.
  final _totalRatings = <String, (double, int, DateTime)>{};

  /// Mağazadaki genel puan: her vitrinin iTunes lookup puanı, oy sayısıyla
  /// ağırlıklı ortalanır (App Store puanı ülke ülke tutar). Oy yoksa null.
  Future<(double, int)?> _totalRating(String appId) async {
    final hit = _totalRatings[appId];
    if (hit != null &&
        DateTime.now().difference(hit.$3) < const Duration(hours: 6)) {
      return (hit.$1, hit.$2);
    }
    var sum = 0.0;
    var count = 0;
    for (var i = 0; i < _storefronts.length; i += 25) {
      final results = await Future.wait([
        for (final c in _storefronts.skip(i).take(25))
          _http
              .get(
                Uri.parse(
                  'https://itunes.apple.com/lookup?id=$appId&country=$c',
                ),
              )
              .then<http.Response?>((r) => r)
              .catchError((_) => null),
      ]);
      for (final res in results) {
        if (res == null || res.statusCode != 200) continue;
        final list = (jsonDecode(res.body) as Map)['results'] as List? ?? [];
        if (list.isEmpty) continue;
        final r = list.first as Map;
        final n = (r['userRatingCount'] as num?)?.toInt() ?? 0;
        final avg = (r['averageUserRating'] as num?)?.toDouble();
        if (n == 0 || avg == null) continue;
        sum += avg * n;
        count += n;
      }
    }
    if (count == 0) return null;
    _totalRatings[appId] = (sum / count, count, DateTime.now());
    return (sum / count, count);
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
    if (!RegExp(r'^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$')
        .hasMatch(issuerId)) {
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
