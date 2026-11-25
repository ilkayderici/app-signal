import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;

import 'fx.dart';
import 'store_series.dart';

/// Play Console toplu raporlarından (Cloud Storage kovası) kurulum, gelir,
/// abone ve yorumları okur; yalnız salt okuma Cloud Storage izni ister. Ya Google girişi (kullanıcının kendi Play Console erişimi) ya da
/// servis hesabı kullanılır; servis hesabına Play Console'da "Uygulama
/// bilgilerini görüntüleme ve toplu raporları indirme" izni verilmeli.
class PlayClient {
  PlayClient._(this._client, this.email, this.bucket);

  static const _api = 'https://storage.googleapis.com/storage/v1';
  static const scopes = [
    'https://www.googleapis.com/auth/devstorage.read_only',
  ];

  final AutoRefreshingAuthClient _client;

  /// Servis hesabının e-postası; Google girişinde null.
  final String? email;
  final String bucket;

  /// "gs://pubsite_prod_123/stats/..." ya da yalnız kova adı kabul edilir.
  /// Play Console sayfa adresi de olur: kova adı çoğu hesapta
  /// `pubsite_prod_<geliştirici kimliği>`'dir (eski hesaplarda rev_ ekli olabilir;
  /// o zaman 404 döner ve kullanıcı URI'yi kopyalar).
  static String normalizeBucket(String input) {
    var s = input.trim();
    final dev = RegExp(r'play\.google\.com/console/.*developers/(\d+)')
        .firstMatch(s);
    if (dev != null) return 'pubsite_prod_${dev.group(1)}';
    if (s.startsWith('gs://')) s = s.substring(5);
    return s.split('/').first;
  }

  static Future<PlayClient> connect(String json, String bucket) async {
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException {
      throw const StoreException(
        'Dosya okunamadı: geçerli bir JSON değil. Google Cloud > IAM > '
        'Servis hesapları > Anahtarlar\'dan indirilen JSON dosyasını seçin.',
      );
    }
    if (decoded is! Map<String, dynamic> ||
        decoded['type'] != 'service_account') {
      throw const StoreException(
        'Bu dosya bir servis hesabı anahtarı değil. OAuth istemci dosyası '
        'değil, servis hesabının JSON anahtarı gerekiyor.',
      );
    }
    final map = decoded;
    checkBucket(bucket);
    final creds = ServiceAccountCredentials.fromJson(map);
    final client = await clientViaServiceAccount(creds, scopes);
    return PlayClient._(client, creds.email, normalizeBucket(bucket));
  }

  /// Google girişinden alınan yenileme jetonuyla istemci kurar.
  static PlayClient fromToken(ClientId id, String refresh, String bucket) {
    checkBucket(bucket);
    return PlayClient._(
      autoRefreshingClient(
        id,
        AccessCredentials(
          AccessToken('Bearer', '', DateTime.utc(1970)),
          refresh,
          scopes,
        ),
        http.Client(),
      ),
      null,
      normalizeBucket(bucket),
    );
  }

  static void checkBucket(String bucket) {
    if (!normalizeBucket(bucket).startsWith('pubsite_prod_')) {
      throw StoreException(
        '${bucket.contains('play.google.com') ? 'Bu Play Console sayfa '
                  'adresi, Cloud Storage URI değil. ' : ''}'
        'Cloud Storage URI gs://pubsite_prod_ ile başlamalı. Play Console > '
        'Raporları indir > İstatistikler\'deki "Cloud Storage URI\'sini '
        'kopyala" düğmesiyle alın.',
      );
    }
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
    final money = await revenue(months: months, from: from, package: package);
    return StoreSeries(
      byDate,
      revenue: money == null
          ? null
          : {for (final d in byDate.keys) d: money[d] ?? 0},
    );
  }

  /// Satış raporundan günlük tahmini net gelir (USD): vergisiz fiyatın
  /// %85'i, iadeler düşülür. "Finansal verileri görüntüleme" izni ya da kur
  /// yoksa null.
  Future<Map<String, double>?> revenue({
    required Set<String> months,
    required String from,
    String? package,
  }) async {
    final byDate = <String, Map<String, double>>{};
    for (final m in months) {
      final name = 'sales/salesreport_$m.zip';
      final res = await _client.get(
        Uri.parse('$_api/b/$bucket/o/${Uri.encodeComponent(name)}?alt=media'),
      );
      if (res.statusCode == 404) {
        debugPrint('Play gelir: $name yok (404)');
        continue;
      }
      if (res.statusCode != 200) {
        debugPrint(
          'Play gelir: $name HTTP ${res.statusCode} '
          '${res.body.length > 300 ? res.body.substring(0, 300) : res.body}',
        );
        return null;
      }
      final Archive zip;
      try {
        zip = ZipDecoder().decodeBytes(res.bodyBytes);
      } catch (e) {
        debugPrint('Play gelir: $name zip açılamadı: $e');
        return null;
      }
      for (final f in zip.files) {
        if (!f.isFile || !f.name.toLowerCase().endsWith('.csv')) continue;
        for (final r in _parseCsv(f.content)) {
          final date = r['Order Charged Date'] ?? '';
          if (date.compareTo(from) < 0) continue;
          if (package != null && r['Product ID'] != package) continue;
          final status = (r['Financial Status'] ?? '').toLowerCase();
          final sign = status.contains('refund')
              ? -1
              : status.contains('charged')
              ? 1
              : 0;
          if (sign == 0) continue;
          final price =
              double.tryParse((r['Item Price'] ?? '').replaceAll(',', '')) ?? 0;
          addMoney(
            byDate.putIfAbsent(date, () => {}),
            r['Currency of Sale'] ?? '',
            sign * price * 0.85,
          );
        }
      }
    }
    final rates = await Fx.rates();
    if (rates == null) {
      debugPrint('Play gelir: kurlar alınamadı');
      return null;
    }
    debugPrint(
      'Play gelir: ${byDate.length} gün, birimler '
      '${{for (final m in byDate.values) ...m.keys}}',
    );
    return {for (final e in byDate.entries) e.key: ?Fx.toUsd(e.value, rates)};
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

  /// Son 7 günün yorumları, kovadaki aylık yorum raporlarından
  /// (`reviews/reviews_<paket>_<ay>.csv`; Play günde bir günceller). [package]
  /// verilirse yalnız o uygulama. Kovaya erişim yoksa null.
  Future<RatingSummary?> ratings({String? package}) async {
    final now = DateTime.now();
    final since = now.subtract(const Duration(days: 7));
    String month(DateTime d) =>
        '${d.year}${d.month.toString().padLeft(2, '0')}';
    final stars = <int>[];
    final low = <Review>[];
    try {
      for (final m in {month(since), month(now)}) {
        final files = await _list('reviews/reviews_${package ?? '*'}_$m.csv');
        for (final rows in await Future.wait(files.map(_download))) {
          for (final r in rows) {
            final star = int.tryParse(r['Star Rating'] ?? '');
            final millis = int.tryParse(
              r['Review Last Update Millis Since Epoch'] ??
                  r['Review Submit Millis Since Epoch'] ??
                  '',
            );
            if (star == null || millis == null) continue;
            final at = DateTime.fromMillisecondsSinceEpoch(millis);
            if (at.isBefore(since)) continue;
            stars.add(star);
            if (!Review.isLow(star, at)) continue;
            final pkg = r['Package Name'] ?? package ?? '';
            final link = r['Review Link'] ?? '';
            final id = RegExp(r'reviewid=([^&]+)').firstMatch(link)?.group(1);
            final title = r['Review Title'] ?? '';
            final text = r['Review Text'] ?? '';
            low.add(
              Review(
                id: id != null && id.startsWith('gp:')
                    ? id
                    : 'gp:${id ?? '$pkg:${r['Review Submit Millis Since Epoch']}'}',
                source: 'Google Play',
                appId: pkg,
                stars: star,
                text: [title, text].where((t) => t.isNotEmpty).join(' - '),
                at: at,
              ),
            );
          }
        }
      }
    } on StoreException {
      return null;
    }
    low.sort((a, b) => b.at.compareTo(a.at));
    return RatingSummary.of(stars, low: low);
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
      401 when email == null =>
        'Google Play: Google girişinin süresi dolmuş ya da izni geri '
            'alınmış. Ayarlar\'dan yeniden giriş yapın.',
      401 =>
        'Google Play: servis hesabı anahtarı geçersiz ya da silinmiş. Google '
            'Cloud\'da bu hesap için yeni bir JSON anahtarı oluşturun.',
      403 when email == null =>
        'Google Play: Google hesabınız rapor deposunu okuyamıyor. Play Console\'a '
            'erişimi olan hesapla giriş yapın; hesabın "Uygulama bilgilerini '
            'görüntüleme ve toplu raporları indirme" izni olmalı.',
      403 =>
        'Google Play: $email rapor deposunu okuyamıyor. Play Console > '
            'Kullanıcılar ve izinler\'de "Uygulama bilgilerini görüntüleme ve '
            'toplu raporları indirme" izni verin (yansıması bir gün sürebilir).',
      404 =>
        'Google Play: "$bucket" bulunamadı. Cloud Storage URI\'yi kontrol edin.',
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
    final rows = _rows(text);
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

  /// Tırnak içinde virgül, satır sonu ve "" kaçışını destekleyen CSV ayrıştırıcı
  /// (yorum metinleri çok satırlı olabilir). Boş satırlar atlanır.
  static List<List<String>> _rows(String text) {
    final rows = <List<String>>[];
    var row = <String>[];
    final cur = StringBuffer();
    var quoted = false;
    void endRow() {
      row.add(cur.toString());
      cur.clear();
      if (row.any((c) => c.trim().isNotEmpty)) rows.add(row);
      row = <String>[];
    }

    for (var i = 0; i < text.length; i++) {
      final ch = text[i];
      if (quoted) {
        if (ch == '"') {
          if (i + 1 < text.length && text[i + 1] == '"') {
            cur.write('"');
            i++;
          } else {
            quoted = false;
          }
        } else {
          cur.write(ch);
        }
      } else if (ch == '"') {
        quoted = true;
      } else if (ch == ',') {
        row.add(cur.toString());
        cur.clear();
      } else if (ch == '\n') {
        endRow();
      } else if (ch != '\r') {
        cur.write(ch);
      }
    }
    if (cur.isNotEmpty || row.isNotEmpty) endRow();
    return rows;
  }

  /// Sütun adları zamanla değişebiliyor; başlığı parçayla eşleştirir.
  static int _pick(Map<String, String> row, String part) {
    for (final e in row.entries) {
      if (e.key.toLowerCase().contains(part)) return int.tryParse(e.value) ?? 0;
    }
    return 0;
  }
}
