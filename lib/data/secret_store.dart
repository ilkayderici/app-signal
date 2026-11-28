import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Anahtar dosyalarının içeriği yalnız burada, işletim sisteminin şifre
/// kasasında (Mac: Anahtar Zinciri, Windows: Kimlik Bilgisi Yöneticisi) durur.
/// Diske düz dosya olarak yazılmaz.
class SecretStore {
  static const _storage = FlutterSecureStorage(
    // İmzasız/ad-hoc derlemede veri koruma anahtar zinciri yetki ister;
    // klasik anahtar zinciri yetkisiz çalışır.
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );

  static const ga4Key = 'ga4_service_account';
  static const appStoreKey = 'appstore_p8';
  static const playKey = 'play_service_account';
  static const admobClientKey = 'admob_oauth_client';
  static const admobRefreshKey = 'admob_refresh_token';
  static const ga4RefreshKey = 'ga4_refresh_token';
  static const playRefreshKey = 'play_refresh_token';

  Future<String?> read(String key) => _storage.read(key: key);

  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  Future<void> delete(String key) => _storage.delete(key: key);

  Future<void> deleteAll() => _storage.deleteAll();

  /// Eski (ad-hoc imzalı) derlemenin yazdığı kayıtlara her okumada izin
  /// sorulur. Bir kez silip yeniden yazınca kayıt bu imzaya geçer; geliştirici
  /// sertifikasıyla imza derlemeden derlemeye değişmediği için soru biter.
  Future<void> adopt(SharedPreferences prefs) async {
    if (!Platform.isMacOS) return;
    const flag = 'secrets.adopted.v1';
    if (prefs.getBool(flag) ?? false) return;
    for (final key in const [ga4Key, appStoreKey, playKey]) {
      final value = await read(key);
      if (value == null) continue;
      await delete(key);
      await write(key, value);
    }
    await prefs.setBool(flag, true);
  }
}
