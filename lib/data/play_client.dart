import 'dart:convert';

import 'package:googleapis_auth/auth_io.dart';

import 'store_series.dart';

/// Play Console toplu raporlarından (Cloud Storage kovası) günlük kurulumları
/// okur. Servis hesabına Play Console'da "Uygulama bilgilerini görüntüleme ve
/// toplu raporları indirme" izni verilmeli.
class PlayClient {
  PlayClient._(this._client, this.email, this.bucket);

  static const _api = 'https://storage.googleapis.com/storage/v1';

  final AutoRefreshingAuthClient _client;
  final String email;
  final String bucket;

  /// "gs://pubsite_prod_123/stats/..." ya da yalnız kova adı kabul edilir.
  static String normalizeBucket(String input) {
    var s = input.trim();
    if (s.startsWith('gs://')) s = s.substring(5);
    return s.split('/').first;
  }

  static Future<PlayClient> connect(String json, String bucket) async {
    final map = jsonDecode(json) as Map<String, dynamic>;
    if (map['type'] != 'service_account') {
      throw const StoreException('Bu dosya bir servis hesabı anahtarı değil.');
    }
    final creds = ServiceAccountCredentials.fromJson(map);
    final client = await clientViaServiceAccount(creds, [
      'https://www.googleapis.com/auth/devstorage.read_only',
      'https://www.googleapis.com/auth/androidpublisher',
    ]);
    return PlayClient._(client, creds.email, normalizeBucket(bucket));
  }

  void close() => _client.close();

  /// Son [days] günün kullanıcı kurulumları. [package] verilirse yalnız o
  /// uygulama, yoksa tüm uygulamaların toplamı.
  Future<StoreSeries> series({int days = 14, String? package}) async {
    final now = DateTime.now();
    final from = ymd(now.subtract(Duration(days: days)));
    String month(DateTime d) =>
        '${d.year}${d.month.toString().padLeft(2, '0')}';
    final months = {month(now.subtract(Duration(days: days))), month(now)};

    final byDate = <String, int>{};
    for (final m in months) {
      final files = await _list(
        'stats/installs/installs_${package ?? '*'}_${m}_overview.csv',
      );
      final csvs = await Future.wait(files.map(_download));
      for (final rows in csvs) {
        for (final r in rows) {
          final date = r['Date'] ?? '';
          if (date.compareTo(from) < 0) continue;
          byDate[date] = (byDate[date] ?? 0) + _pick(r, 'daily user installs');
        }
      }
    }
    return StoreSeries(byDate);
  }

  /// Aktif abone sayısı (abonelik raporlarının en yeni günü). Rapor ya da
  /// yetki yoksa null.
  Future<int?> subscribers({String? package}) async {
    final now = DateTime.now();
    String month(DateTime d) =>
        '${d.year}${d.month.toString().padLeft(2, '0')}';
    try {
      for (final m in [month(now), month(DateTime(now.year, now.month, 0))]) {
        final files = await _list(
          'financial-stats/subscriptions/'
          'subscriptions_${package ?? '*'}_${m}_*.csv',
        );
        if (files.isEmpty) continue;
        var total = 0;
        for (final rows in await Future.wait(files.map(_download))) {
          final last = rows
              .map((r) => r['Date'] ?? '')
              .fold('', (a, b) => b.compareTo(a) > 0 ? b : a);
          for (final r in rows) {
            if (r['Date'] == last) total += _pick(r, 'active subscriptions');
          }
        }
        return total;
      }
    } on StoreException {
      return null;
    }
    return null;
  }

  /// Kovadaki kurulum dosyalarından paket adları.
  Future<Set<String>> packages() async {
    final files = await _list('stats/installs/installs_*_overview.csv');
    final re = RegExp(r'installs_(.+)_\d{6}_overview\.csv$');
    return {for (final f in files) ?re.firstMatch(f)?.group(1)};
  }

  /// Son yorumlar (Play API yalnız son 7 günü verir). [package] verilirse
  /// yalnız o uygulama. İzin yoksa null.
  Future<RatingSummary?> ratings({String? package}) async {
    final stars = <int>[];
    final low = <Review>[];
    var allowed = false;
    for (final pkg in package != null ? {package} : await packages()) {
      String? page;
      do {
        final uri = Uri.parse(
          'https://androidpublisher.googleapis.com/'
          'androidpublisher/v3/applications/$pkg/reviews',
        ).replace(queryParameters: {'maxResults': '100', 'token': ?page});
        final res = await _client.get(uri);
        if (res.statusCode != 200) break;
        allowed = true;
        final body = jsonDecode(res.body) as Map;
        for (final r in (body['reviews'] as List? ?? const [])) {
          final c = (r['comments'] as List).first['userComment'] as Map?;
          final star = c?['starRating'];
          if (star is! num) continue;
          stars.add(star.toInt());
          final secs = int.tryParse('${c?['lastModified']?['seconds']}');
          final at = secs == null
              ? DateTime.now()
              : DateTime.fromMillisecondsSinceEpoch(secs * 1000);
          if (Review.isLow(star.toInt(), at)) {
            low.add(
              Review(
                id: 'gp:${r['reviewId']}',
                source: 'Google Play',
                appId: pkg,
                stars: star.toInt(),
                text: '${c?['text'] ?? ''}'.trim(),
                at: at,
              ),
            );
          }
        }
        page = (body['tokenPagination'] as Map?)?['nextPageToken'] as String?;
      } while (page != null);
    }
    low.sort((a, b) => b.at.compareTo(a.at));
    return allowed ? RatingSummary.of(stars, low: low) : null;
  }

  Future<List<String>> _list(String glob) async {
    final out = <String>[];
    String? page;
    do {
      final uri = Uri.parse('$_api/b/$bucket/o').replace(
        queryParameters: {
          'matchGlob': glob,
          'fields': 'items(name),nextPageToken',
          'pageToken': ?page,
        },
      );
      final body = jsonDecode(utf8.decode(await _get(uri))) as Map;
      for (final i in (body['items'] as List? ?? const [])) {
        out.add(i['name'] as String);
      }
      page = body['nextPageToken'] as String?;
    } while (page != null);
    return out;
  }

  Future<List<Map<String, String>>> _download(String name) async {
    final uri = Uri.parse(
      '$_api/b/$bucket/o/${Uri.encodeComponent(name)}?alt=media',
    );
    return _parseCsv(await _get(uri));
  }

  Future<List<int>> _get(Uri uri) async {
    final res = await _client.get(uri);
    if (res.statusCode == 200) return res.bodyBytes;
    throw StoreException(switch (res.statusCode) {
      403 =>
        'Google Play: $email kovayı okuyamıyor. Play Console > '
            'Kullanıcılar ve izinler\'de "Uygulama bilgilerini görüntüleme ve '
            'toplu raporları indirme" izni verin (yansıması bir gün sürebilir).',
      404 => 'Google Play: "$bucket" kovası bulunamadı.',
      _ => 'Google Play: HTTP ${res.statusCode}',
    });
  }

  /// Play CSV'leri çoğunlukla UTF-16LE (BOM'lu); bazıları UTF-8.
  static List<Map<String, String>> _parseCsv(List<int> b) {
    String text;
    if (b.length >= 2 && b[0] == 0xFF && b[1] == 0xFE) {
      final units = <int>[
        for (var i = 2; i + 1 < b.length; i += 2) b[i] | (b[i + 1] << 8),
      ];
      text = String.fromCharCodes(units);
    } else {
      text = utf8.decode(b, allowMalformed: true).replaceFirst('﻿', '');
    }
    final rows = [
      for (final line in const LineSplitter().convert(text))
        if (line.trim().isNotEmpty) _cells(line),
    ];
    if (rows.isEmpty) return const [];
    final head = [for (final h in rows.first) h.trim()];
    return [
      for (final r in rows.skip(1))
        {
          for (var i = 0; i < head.length; i++)
            head[i]: i < r.length ? r[i].trim() : '',
        },
    ];
  }

  static List<String> _cells(String line) {
    final out = <String>[];
    final cur = StringBuffer();
    var quoted = false;
    for (final ch in line.split('')) {
      if (ch == '"') {
        quoted = !quoted;
      } else if (ch == ',' && !quoted) {
        out.add(cur.toString());
        cur.clear();
      } else {
        cur.write(ch);
      }
    }
    out.add(cur.toString());
    return out;
  }

  /// Sütun adları zamanla değişebiliyor; başlığı parçayla eşleştirir.
  static int _pick(Map<String, String> row, String part) {
    for (final e in row.entries) {
      if (e.key.toLowerCase().contains(part)) return int.tryParse(e.value) ?? 0;
    }
    return 0;
  }
}
