import 'dart:io';

import 'package:auto_updater/auto_updater.dart';
import 'package:flutter/foundation.dart';

/// Tam otomatik güncelleme: macOS'ta Sparkle, Windows'ta WinSparkle.
///
/// Uygulama günde bir kez GitHub'daki son sürümün appcast dosyasına bakar.
/// Yeni sürüm varsa Sparkle kendi penceresini açar, indirir, imzayı (EdDSA)
/// doğrular, kurar ve yeniden başlatır.
class Updater {
  Updater._();

  static const _base =
      'https://github.com/ilkayderici/app-signal/releases/latest/download';

  static String get feedUrl =>
      '$_base/${Platform.isWindows ? 'appcast-windows.xml' : 'appcast.xml'}';

  /// Hata ayıklama derlemesinde çalışmaz; yerel derleme güncellenmesin.
  static Future<void> start() async {
    if (kDebugMode) return;
    try {
      await autoUpdater.setFeedURL(feedUrl);
      await autoUpdater.setScheduledCheckInterval(86400);
      await autoUpdater.checkForUpdates(inBackground: true);
    } catch (e) {
      debugPrint('Güncelleme denetimi başlamadı: $e');
    }
  }

  /// Menüden elle denetim. Sparkle sonucu kendi penceresinde gösterir.
  static Future<void> checkNow() async {
    try {
      await autoUpdater.setFeedURL(feedUrl);
      await autoUpdater.checkForUpdates();
    } catch (e) {
      debugPrint('Güncelleme denetimi başarısız: $e');
    }
  }
}
