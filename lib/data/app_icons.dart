import 'dart:convert';

import 'package:http/http.dart' as http;

/// Uygulama ikonunun adresini mağazaların herkese açık sayfalarından bulur.
/// Önce App Store arama servisi, yoksa Google Play sayfasındaki og:image.
Future<String?> findAppIcon({String? appleId, String? playPackage}) async {
  final client = http.Client();
  try {
    if (appleId != null) {
      for (final country in ['us', 'tr']) {
        final res = await client.get(
          Uri.parse(
            'https://itunes.apple.com/lookup?id=$appleId&country=$country',
          ),
        );
        if (res.statusCode != 200) continue;
        final results = (jsonDecode(res.body) as Map)['results'] as List?;
        final url = results?.firstOrNull?['artworkUrl512'] as String?;
        if (url != null) return url;
      }
    }
    if (playPackage != null) {
      final res = await client.get(
        Uri.parse(
          'https://play.google.com/store/apps/details?id=$playPackage&hl=en',
        ),
      );
      if (res.statusCode == 200) {
        final m = RegExp(r'<meta property="og:image" content="([^"]+)"')
            .firstMatch(res.body);
        if (m != null) return m.group(1);
      }
    }
    return null;
  } catch (_) {
    return null;
  } finally {
    client.close();
  }
}
