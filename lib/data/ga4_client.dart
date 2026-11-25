import 'dart:convert';

import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;

/// GA4'e yalnız okuma izniyle bağlanan istemci. Servis hesabı JSON'u ya da
/// Google girişiyle kimlik doğrular; Admin API'den mülkleri, Data API'den
/// raporları çeker.
class Ga4Client {
  Ga4Client._(this._client, this.email);

  static const scopes = ['https://www.googleapis.com/auth/analytics.readonly'];
  static const _data = 'https://analyticsdata.googleapis.com/v1beta';
  static const _admin = 'https://analyticsadmin.googleapis.com/v1beta';

  final AutoRefreshingAuthClient _client;

  /// Servis hesabının e-postası; kullanıcı bunu GA4'e "Görüntüleyen" ekler.
  /// Google girişinde null (kullanıcının kendi erişimi kullanılır).
  final String? email;

  /// JSON metninden istemci kurar. Dosya servis hesabı değilse hata verir.
  static Future<Ga4Client> connect(String serviceAccountJson) async {
    final map = jsonDecode(serviceAccountJson) as Map<String, dynamic>;
    if (map['type'] != 'service_account') {
      throw const FormatException('Bu dosya bir servis hesabı anahtarı değil.');
    }
    final creds = ServiceAccountCredentials.fromJson(map);
    final client = await clientViaServiceAccount(creds, scopes);
    return Ga4Client._(client, creds.email);
  }

  /// Google girişinden alınan yenileme jetonuyla istemci kurar.
  static Ga4Client fromToken(ClientId id, String refresh) => Ga4Client._(
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
  );

  void close() => _client.close();

  /// Servis hesabının görebildiği tüm GA4 mülkleri.
  Future<List<Ga4Property>> properties() async {
    final out = <Ga4Property>[];
    String? page;
    do {
      final uri = Uri.parse('$_admin/accountSummaries')
          .replace(queryParameters: {'pageSize': '200', 'pageToken': ?page});
      final body = await _get(uri);
      for (final acc in (body['accountSummaries'] as List? ?? const [])) {
        final accName = acc['displayName'] as String? ?? '';
        for (final p in (acc['propertySummaries'] as List? ?? const [])) {
          out.add(
            Ga4Property(
              id: (p['property'] as String).split('/').last,
              name: p['displayName'] as String? ?? '',
              account: accName,
            ),
          );
        }
      }
      page = body['nextPageToken'] as String?;
    } while (page != null && page.isNotEmpty);
    return out;
  }

  /// Mülkün uygulama akışları: akış kimliği, ad ve paket/bundle kimliği.
  Future<List<({String streamId, String name, String appId})>> appStreams(
    String propertyId,
  ) async {
    final body = await _get(
      Uri.parse('$_admin/properties/$propertyId/dataStreams?pageSize=200'),
    );
    return [
      for (final s in (body['dataStreams'] as List? ?? const []))
        if ((s['iosAppStreamData']?['bundleId'] ??
                s['androidAppStreamData']?['packageName'])
            case final String appId)
          (
            streamId: (s['name'] as String).split('/').last,
            name: s['displayName'] as String? ?? appId,
            appId: appId,
          ),
    ];
  }

  /// [streamIds] verilirse rapor yalnız bu akışlara süzülür.
  static Map<String, Object> _streamFilter(List<String>? streamIds) =>
      streamIds == null
      ? const {}
      : {
          'dimensionFilter': {
            'filter': {
              'fieldName': 'streamId',
              'inListFilter': {'values': streamIds},
            },
          },
        };

  /// Mülkün özel boyut ve ölçüleri (oyun boyutunu seçmek için).
  Future<Ga4Metadata> metadata(String propertyId) async {
    final body = await _get(
      Uri.parse('$_data/properties/$propertyId/metadata'),
    );
    List<Ga4Field> custom(String key) => [
      for (final f in (body[key] as List? ?? const []))
        if (f['customDefinition'] == true)
          Ga4Field(f['apiName'] as String, f['uiName'] as String? ?? ''),
    ];
    return Ga4Metadata(
      dimensions: custom('dimensions')
          .where((f) => f.apiName.startsWith('customEvent:'))
          .toList(),
      metrics: custom('metrics')
          .where((f) => f.apiName.startsWith('customEvent:'))
          .toList(),
    );
  }

  /// Data API runReport. Satırları {alan adı: değer} haritası olarak döner.
  Future<List<Map<String, String>>> report(
    String propertyId, {
    required List<Map<String, String>> dateRanges,
    List<String> dimensions = const [],
    required List<String> metrics,
    String? orderByMetric,
    int limit = 50,
    List<String>? streamIds,
  }) async {
    final body = await _post(
      Uri.parse('$_data/properties/$propertyId:runReport'),
      {
        ..._streamFilter(streamIds),
        'dateRanges': dateRanges,
        'dimensions': [
          for (final d in dimensions) {'name': d},
        ],
        'metrics': [
          for (final m in metrics) {'name': m},
        ],
        if (orderByMetric != null)
          'orderBys': [
            {
              'metric': {'metricName': orderByMetric},
              'desc': true,
            },
          ],
        'limit': limit,
      },
    );
    return _rows(body);
  }

  /// Günlük kohortlarla tutunma. [cohortDays] her kohortun ilk oturum günü
  /// (yyyy-MM-dd). Satırlar: cohort (kohort adı = gün), cohortNthDay,
  /// cohortActiveUsers, cohortTotalUsers.
  Future<List<Map<String, String>>> cohortReport(
    String propertyId, {
    required List<String> cohortDays,
    required int endOffset,
    List<String>? streamIds,
  }) async {
    final body = await _post(
      Uri.parse('$_data/properties/$propertyId:runReport'),
      {
        ..._streamFilter(streamIds),
        'dimensions': [
          {'name': 'cohort'},
          {'name': 'cohortNthDay'},
        ],
        'metrics': [
          {'name': 'cohortActiveUsers'},
          {'name': 'cohortTotalUsers'},
        ],
        'cohortSpec': {
          'cohorts': [
            for (final d in cohortDays)
              {
                'name': d,
                'dimension': 'firstSessionDate',
                'dateRange': {'startDate': d, 'endDate': d},
              },
          ],
          'cohortsRange': {
            'granularity': 'DAILY',
            'startOffset': 0,
            'endOffset': endOffset,
          },
        },
        'limit': 1000,
      },
    );
    return _rows(body);
  }

  /// Son 30 dakikada aktif kullanıcı sayısı.
  Future<int> realtimeActiveUsers(
    String propertyId, {
    List<String>? streamIds,
  }) async {
    final body = await _post(
      Uri.parse('$_data/properties/$propertyId:runRealtimeReport'),
      {
        ..._streamFilter(streamIds),
        'metrics': [
          {'name': 'activeUsers'},
        ],
      },
    );
    final rows = _rows(body);
    return rows.isEmpty ? 0 : int.tryParse(rows.first['activeUsers']!) ?? 0;
  }

  List<Map<String, String>> _rows(Map<String, dynamic> body) {
    final dims = [
      for (final h in (body['dimensionHeaders'] as List? ?? const []))
        h['name'] as String,
    ];
    final mets = [
      for (final h in (body['metricHeaders'] as List? ?? const []))
        h['name'] as String,
    ];
    return [
      for (final r in (body['rows'] as List? ?? const []))
        {
          for (var i = 0; i < dims.length; i++)
            dims[i]: r['dimensionValues'][i]['value'] as String,
          for (var i = 0; i < mets.length; i++)
            mets[i]: r['metricValues'][i]['value'] as String,
        },
    ];
  }

  Future<Map<String, dynamic>> _get(Uri uri) async =>
      _decode(await _client.get(uri));

  Future<Map<String, dynamic>> _post(Uri uri, Object body) async => _decode(
    await _client.post(
      uri,
      headers: {'content-type': 'application/json'},
      body: jsonEncode(body),
    ),
  );

  Map<String, dynamic> _decode(http.Response res) {
    final body = res.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode >= 400) {
      final err = body['error'] as Map<String, dynamic>?;
      throw Ga4Exception(
        res.statusCode,
        err?['message'] as String? ?? 'HTTP ${res.statusCode}',
      );
    }
    return body;
  }
}

class Ga4Property {
  const Ga4Property({
    required this.id,
    required this.name,
    required this.account,
  });

  final String id;
  final String name;
  final String account;
}

class Ga4Field {
  const Ga4Field(this.apiName, this.uiName);

  final String apiName;
  final String uiName;

  String get label => uiName.isEmpty || uiName == apiName.split(':').last
      ? apiName.split(':').last
      : '$uiName (${apiName.split(':').last})';
}

class Ga4Metadata {
  const Ga4Metadata({required this.dimensions, required this.metrics});

  final List<Ga4Field> dimensions;
  final List<Ga4Field> metrics;

  /// Adında aranan sözcük geçen ilk alan; yoksa null.
  static String? guess(List<Ga4Field> fields, List<String> words) {
    for (final w in words) {
      for (final f in fields) {
        if (f.apiName.toLowerCase().contains(w)) return f.apiName;
      }
    }
    return null;
  }
}

class Ga4Exception implements Exception {
  const Ga4Exception(this.status, this.message);

  final int status;
  final String message;

  @override
  String toString() => status == 403
      ? 'Erişim yok. Servis hesabını GA4 mülküne "Görüntüleyen" olarak ekleyin.'
      : message;
}
