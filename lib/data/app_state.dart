import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_icons.dart';
import 'drops.dart';

import 'appstore_client.dart';
import 'demo.dart';
import 'ga4_client.dart';
import 'admob_client.dart';
import 'play_client.dart';
import 'secret_store.dart';
import 'store_series.dart';

/// GA4 ayarları: hangi mülk, oyunlar hangi boyutta, süre ve gelir hangi
/// ölçüde. Gizli değil; tercih dosyasında durur.
class Ga4Settings {
  const Ga4Settings({
    required this.propertyId,
    required this.propertyName,
    this.gameDimension,
    this.durationMetric,
    this.revenueMetric,
    this.gameLimit = 5,
  });

  final String propertyId;
  final String propertyName;
  final String? gameDimension;
  final String? durationMetric;
  final String? revenueMetric;

  /// Panelde gösterilecek en çok oyun sayısı; 0 hepsi demek.
  final int gameLimit;

  static Ga4Settings? load(SharedPreferences p) {
    final id = p.getString('ga4.property');
    if (id == null) return null;
    return Ga4Settings(
      propertyId: id,
      propertyName: p.getString('ga4.propertyName') ?? id,
      gameDimension: p.getString('ga4.gameDimension'),
      durationMetric: p.getString('ga4.durationMetric'),
      revenueMetric: p.getString('ga4.revenueMetric'),
      gameLimit: p.getInt('ga4.gameLimit') ?? 5,
    );
  }

  Future<void> save(SharedPreferences p) async {
    await p.setString('ga4.property', propertyId);
    await p.setString('ga4.propertyName', propertyName);
    Future<void> opt(String k, String? v) =>
        v == null ? p.remove(k) : p.setString(k, v);
    await opt('ga4.gameDimension', gameDimension);
    await opt('ga4.durationMetric', durationMetric);
    await opt('ga4.revenueMetric', revenueMetric);
    await p.setInt('ga4.gameLimit', gameLimit);
  }

  static Future<void> clear(SharedPreferences p) async {
    for (final k in [
      'ga4.property',
      'ga4.propertyName',
      'ga4.gameDimension',
      'ga4.durationMetric',
      'ga4.revenueMetric',
      'ga4.gameLimit',
    ]) {
      await p.remove(k);
    }
  }
}

class GameRow {
  const GameRow({
    required this.id,
    required this.users,
    this.seconds,
    this.revenue,
  });

  final String id;
  final int users;
  final double? seconds;
  final double? revenue;
}

/// Bir yenilemede GA4'ten gelen her şey.
class Ga4Snapshot {
  const Ga4Snapshot({
    required this.realtime,
    required this.today,
    required this.yesterday,
    required this.newToday,
    required this.daily,
    required this.games,
    required this.at,
    this.revenue,
    this.retention,
  });

  final int realtime;
  final int today;
  final int yesterday;
  final int newToday;

  /// Son 14 günün günlük aktif kullanıcısı, eskiden yeniye.
  final List<int> daily;
  final List<GameRow> games;
  final DateTime at;

  /// Gelir ölçüsü seçiliyse bugün, dün ve bu ayın toplamı.
  final RevenueSummary? revenue;

  /// D1/D7/D30 tutunma; kohort raporu alınamazsa null.
  final Retention? retention;
}

/// Yeni oyuncuların ertesi gün (D1), 7. gün (D7) ve 30. gün (D30) dönme
/// oranı, 0-1. Yalnız o günü tamamlanmış kohortların ağırlıklı ortalaması.
class Retention {
  const Retention({
    this.d1,
    this.d7,
    this.d30,
    this.d1Users = 0,
    this.d7Users = 0,
    this.d30Users = 0,
  });

  final double? d1;
  final double? d7;
  final double? d30;

  /// Ortalamaya giren yeni oyuncu sayısı.
  final int d1Users;
  final int d7Users;
  final int d30Users;
}

/// Mağazalarda ve GA4'te aynı paket kimliğiyle eşleşen bir uygulama.
class AppEntry {
  const AppEntry({
    required this.id,
    required this.name,
    this.appleId,
    this.playPackage,
    this.ga4PropertyId,
    this.ga4StreamIds = const [],
  });

  /// Paket / bundle kimliği (com.ornek.oyun).
  final String id;
  final String name;
  final String? appleId;
  final String? playPackage;
  final String? ga4PropertyId;
  final List<String> ga4StreamIds;
}

class RevenueSummary {
  const RevenueSummary({
    required this.today,
    required this.yesterday,
    required this.month,
    this.currency = 'USD',
    this.real = false,
  });

  final double today;
  final double yesterday;
  final double month;
  final String currency;

  /// AdMob raporundan (gerçek); false ise GA4 gelir ölçüsünden (tahmini).
  final bool real;
}

class AppState extends ChangeNotifier {
  AppState._(this._prefs);

  static Future<AppState> create() async {
    final s = AppState._(await SharedPreferences.getInstance());
    s.ga4Settings = Ga4Settings.load(s._prefs);
    s.selectedAppId = s._prefs.getString('app.selected');
    if (demoMode) {
      fillDemo(s);
      return s;
    }
    // Ağ beklenmeden pencere açılsın; veri gelince kartlar dolar.
    unawaited(s._restore());
    s._timer = Timer.periodic(const Duration(minutes: 5), (_) => s.refresh());
    return s;
  }

  final SharedPreferences _prefs;
  final _secrets = SecretStore();
  Timer? _timer;

  Ga4Client? ga4;
  Ga4Settings? ga4Settings;
  Ga4Snapshot? ga4Data;
  String? ga4Error;
  bool loading = false;

  AppStoreClient? appStore;
  StoreSeries? appStoreData;
  RatingSummary? appStoreRating;
  int? appStoreSubs;
  String? appStoreError;

  PlayClient? play;
  StoreSeries? playData;
  RatingSummary? playRating;
  int? playSubs;
  String? playError;

  AdmobClient? admob;
  RevenueSummary? admobData;
  String? admobError;

  /// Bağlı kaynaklarda bulunan uygulamalar ve seçili olan (null = hepsi).
  List<AppEntry> apps = const [];
  String? selectedAppId;

  /// Uygulama kimliği → ikon adresi (kalıcı; mağazaya bir kez sorulur).
  final Map<String, String> icons = {};

  AppEntry? get selectedApp =>
      apps.where((a) => a.id == selectedAppId).firstOrNull;

  /// Seçili uygulama bu kaynakta yoksa true; kart "yok" der.
  bool get appStoreMissing =>
      selectedApp != null && selectedApp!.appleId == null;
  bool get playMissing =>
      selectedApp != null && selectedApp!.playPackage == null;
  bool get ga4Missing =>
      selectedApp != null && selectedApp!.ga4PropertyId == null;

  /// Mağaza verisi günde bir değişir; en çok saatte bir çekilir.
  DateTime? _storesAt;

  /// Yenileme sürerken uygulama değişirse bitince bir tur daha döner.
  bool _again = false;

  /// Son 7 günün 1-2 yıldızlı yorumları, iki mağaza birlikte, yeniden eskiye.
  List<Review> get lowReviews =>
      [...?appStoreRating?.low, ...?playRating?.low]
        ..sort((a, b) => b.at.compareTo(a.at));

  /// Yorumun ait olduğu uygulamanın adı.
  String appName(Review r) {
    for (final a in apps) {
      if (a.appleId == r.appId || a.playPackage == r.appId) return a.name;
    }
    return r.appId;
  }

  /// Son tam günde belirgin düşüşler (seçili uygulama için).
  List<Drop> drops = const [];

  /// Açılışta kayıtlı bağlantılar kasadan okunurken true.
  bool restoring = true;

  bool get ga4Ready => demoMode || ga4 != null && ga4Settings != null;
  bool get appStoreOn => demoMode || appStore != null;
  bool get playOn => demoMode || play != null;
  bool get anyReady =>
      ga4Ready || appStore != null || play != null || admob != null;

  /// Gizli olmayan kayıtlı ayar (ayar pencerelerini doldurmak için).
  String? pref(String key) => _prefs.getString(key);

  Future<void> _restore() async {
    await _secrets.adopt(_prefs);
    final ga4Json = await _secrets.read(SecretStore.ga4Key);
    final ga4Token = await _secrets.read(SecretStore.ga4RefreshKey);
    try {
      if (ga4Token != null) {
        ga4 = Ga4Client.fromToken(
          AdmobClient.clientId(await AdmobClient.builtInClient()),
          ga4Token,
        );
      } else if (ga4Json != null) {
        ga4 = await Ga4Client.connect(ga4Json);
      }
    } catch (e) {
      ga4Error = '$e';
    }
    final p8 = await _secrets.read(SecretStore.appStoreKey);
    if (p8 != null) {
      try {
        appStore = AppStoreClient(
          p8: p8,
          keyId: pref('appstore.keyId') ?? '',
          issuerId: pref('appstore.issuer') ?? '',
          vendor: pref('appstore.vendor') ?? '',
        );
      } catch (e) {
        appStoreError = 'App Store: $e';
      }
    }
    final playJson = await _secrets.read(SecretStore.playKey);
    final bucket = pref('play.bucket');
    if (playJson != null && bucket != null) {
      try {
        play = await PlayClient.connect(playJson, bucket);
      } catch (e) {
        playError = 'Google Play: $e';
      }
    }
    final admobToken = await _secrets.read(SecretStore.admobRefreshKey);
    if (admobToken != null) {
      try {
        final admobJson =
            await _secrets.read(SecretStore.admobClientKey) ??
            await AdmobClient.builtInClient();
        admob = await AdmobClient.connect(admobJson, admobToken);
      } catch (e) {
        admobError = '$e';
      }
    }
    restoring = false;
    notifyListeners();
    await refresh(force: true);
  }

  /// GA4 için kayıtlı servis hesabı JSON'u (Play'de aynısını kullanmak için).
  Future<String?> ga4Json() => _secrets.read(SecretStore.ga4Key);

  /// App Store anahtarını dener; çalışırsa kaydeder. [p8] null ise kayıtlı
  /// anahtar kullanılır.
  Future<void> connectAppStore({
    String? p8,
    required String keyId,
    required String issuerId,
    required String vendor,
  }) async {
    final key = p8 ?? await _secrets.read(SecretStore.appStoreKey);
    if (key == null) throw const StoreException('.p8 anahtar dosyasını seçin.');
    final client = AppStoreClient(
      p8: key,
      keyId: keyId.trim(),
      issuerId: issuerId.trim(),
      vendor: vendor.trim(),
    );
    final data = await client.series();
    await _secrets.write(SecretStore.appStoreKey, key);
    await _prefs.setString('appstore.keyId', client.keyId);
    await _prefs.setString('appstore.issuer', client.issuerId);
    await _prefs.setString('appstore.vendor', client.vendor);
    appStore?.close();
    appStore = client;
    appStoreData = data;
    appStoreError = null;
    notifyListeners();
  }

  Future<void> disconnectAppStore() async {
    await _secrets.delete(SecretStore.appStoreKey);
    for (final k in ['appstore.keyId', 'appstore.issuer', 'appstore.vendor']) {
      await _prefs.remove(k);
    }
    appStore?.close();
    appStore = null;
    appStoreData = null;
    appStoreError = null;
    notifyListeners();
  }

  /// Play kovasını dener; çalışırsa kaydeder. [json] null ise kayıtlı anahtar.
  Future<void> connectPlay({String? json, required String bucket}) async {
    final key = json ?? await _secrets.read(SecretStore.playKey);
    if (key == null) {
      throw const StoreException('Servis hesabı JSON dosyasını seçin.');
    }
    final client = await PlayClient.connect(key, bucket);
    final StoreSeries data;
    try {
      data = await client.series();
    } catch (_) {
      client.close();
      rethrow;
    }
    await _secrets.write(SecretStore.playKey, key);
    await _prefs.setString('play.bucket', client.bucket);
    play?.close();
    play = client;
    playData = data;
    playError = null;
    notifyListeners();
  }

  /// Tarayıcıda Google girişi açar; izin verilince yenileme jetonunu
  /// kaydeder. Uygulamaya gömülü OAuth istemcisini kullanır.
  Future<void> connectAdmob() async {
    final json = await AdmobClient.builtInClient();
    final token = await AdmobClient.signIn(json);
    final client = await AdmobClient.connect(json, token);
    await _secrets.delete(SecretStore.admobClientKey);
    await _secrets.write(SecretStore.admobRefreshKey, token);
    admob?.close();
    admob = client;
    admobError = null;
    await _refreshAdmob(selectedApp);
    notifyListeners();
  }

  Future<void> disconnectAdmob() async {
    await _secrets.delete(SecretStore.admobClientKey);
    await _secrets.delete(SecretStore.admobRefreshKey);
    admob?.close();
    admob = null;
    admobData = null;
    admobError = null;
    notifyListeners();
  }

  Future<void> _refreshAdmob(AppEntry? app) async {
    try {
      final ids = app == null ? null : {?app.appleId, ?app.playPackage, app.id};
      final r = await admob!.earnings(storeIds: ids);
      admobData = r == null
          ? null
          : RevenueSummary(
              today: r.today,
              yesterday: r.yesterday,
              month: r.month,
              currency: admob!.currency,
              real: true,
            );
      admobError = null;
    } catch (e) {
      admobError = '$e';
    }
  }

  Future<void> disconnectPlay() async {
    await _secrets.delete(SecretStore.playKey);
    await _prefs.remove('play.bucket');
    play?.close();
    play = null;
    playData = null;
    playError = null;
    notifyListeners();
  }

  /// Yeni JSON'u dener; çalışırsa kasaya yazar. Mülk seçimi ayrıca yapılır.
  Future<Ga4Client> connectGa4(String json) async {
    final client = await Ga4Client.connect(json);
    await client.properties(); // erişim var mı, hemen anlaşılsın
    await _secrets.write(SecretStore.ga4Key, json);
    await _secrets.delete(SecretStore.ga4RefreshKey);
    ga4?.close();
    ga4 = client;
    ga4Error = null;
    notifyListeners();
    return client;
  }

  /// Tarayıcıda Google girişi; GA4'e kullanıcının kendi erişimiyle bağlanır.
  Future<Ga4Client> connectGa4WithGoogle() async {
    final json = await AdmobClient.builtInClient();
    final token = await AdmobClient.signIn(json, scopes: Ga4Client.scopes);
    final client = Ga4Client.fromToken(AdmobClient.clientId(json), token);
    try {
      await client.properties(); // erişim var mı, hemen anlaşılsın
    } catch (_) {
      client.close();
      rethrow;
    }
    await _secrets.write(SecretStore.ga4RefreshKey, token);
    await _secrets.delete(SecretStore.ga4Key);
    ga4?.close();
    ga4 = client;
    ga4Error = null;
    notifyListeners();
    return client;
  }

  Future<void> saveGa4Settings(Ga4Settings s) async {
    await s.save(_prefs);
    ga4Settings = s;
    ga4Data = null;
    notifyListeners();
    await refresh();
  }

  Future<void> disconnectGa4() async {
    await _secrets.delete(SecretStore.ga4Key);
    await _secrets.delete(SecretStore.ga4RefreshKey);
    await Ga4Settings.clear(_prefs);
    ga4?.close();
    ga4 = null;
    ga4Settings = null;
    ga4Data = null;
    ga4Error = null;
    notifyListeners();
  }

  /// GA4 her çağrıda, mağazalar saatte bir ya da [force] ile yenilenir.
  /// Üstteki seçiciden uygulama değiştirir; null tüm uygulamalar.
  Future<void> selectApp(String? id) async {
    if (id == selectedAppId) return;
    selectedAppId = id;
    if (id == null) {
      await _prefs.remove('app.selected');
    } else {
      await _prefs.setString('app.selected', id);
    }
    ga4Data = null;
    appStoreData = null;
    appStoreRating = null;
    playData = null;
    playRating = null;
    notifyListeners();
    await refresh(force: true);
  }

  /// Uygulama listesini mağazalardan ve GA4 akışlarından toplar.
  Future<void> _discoverApps() async {
    final byId = <String, AppEntry>{};
    AppEntry merge(
      String id, {
      String? name,
      String? appleId,
      String? playPackage,
      String? propertyId,
      String? streamId,
    }) {
      final old = byId[id];
      return byId[id] = AppEntry(
        id: id,
        name: old != null && old.name != id ? old.name : (name ?? id),
        appleId: old?.appleId ?? appleId,
        playPackage: old?.playPackage ?? playPackage,
        ga4PropertyId: old?.ga4PropertyId ?? propertyId,
        ga4StreamIds: [
          ...?old?.ga4StreamIds,
          if (streamId != null &&
              (old?.ga4PropertyId == null || old?.ga4PropertyId == propertyId))
            streamId,
        ],
      );
    }

    await Future.wait([
      if (appStore != null)
        appStore!
            .apps()
            .then((list) {
              for (final a in list) {
                merge(a.bundleId, name: a.name, appleId: a.id);
              }
            })
            .catchError((_) {}),
      if (play != null)
        play!
            .packages()
            .then((list) {
              for (final p in list) {
                merge(p, playPackage: p);
              }
            })
            .catchError((_) {}),
      if (ga4 != null)
        ga4!
            .properties()
            .then((props) async {
              // Önce ayarlı mülk: aynı uygulama birden çok mülkteyse o seçilsin.
              final first = ga4Settings?.propertyId;
              props.sort(
                (a, b) => (a.id == first ? 0 : 1) - (b.id == first ? 0 : 1),
              );
              for (final p in props) {
                final streams = await ga4!
                    .appStreams(p.id)
                    .catchError(
                      (_) => <({String streamId, String name, String appId})>[],
                    );
                for (final s in streams) {
                  merge(
                    s.appId,
                    name: s.name,
                    propertyId: p.id,
                    streamId: s.streamId,
                  );
                }
              }
            })
            .catchError((_) {}),
    ]);
    final list = byId.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    apps = list;
    unawaited(_loadIcons());
  }

  /// Eksik ikonları arka planda bulur ve saklar.
  Future<void> _loadIcons() async {
    for (final a in apps) {
      if (icons.containsKey(a.id)) continue;
      final saved = _prefs.getString('icon.${a.id}');
      final url =
          saved ??
          await findAppIcon(appleId: a.appleId, playPackage: a.playPackage);
      if (url == null) continue;
      icons[a.id] = url;
      if (saved == null) await _prefs.setString('icon.${a.id}', url);
      notifyListeners();
    }
  }

  Future<void> refresh({bool force = false}) async {
    if (loading) {
      _again = true;
      return;
    }
    if (!anyReady || demoMode) return;
    final stores =
        force ||
        _storesAt == null ||
        DateTime.now().difference(_storesAt!) > const Duration(hours: 1);
    loading = true;
    notifyListeners();
    if (stores || apps.isEmpty) await _discoverApps();
    final app = selectedApp;
    await Future.wait([
      if (ga4Ready) _refreshGa4(app),
      if (stores && appStore != null) _refreshAppStore(app),
      if (stores && play != null) _refreshPlay(app),
      if (admob != null) _refreshAdmob(app),
    ]);
    if (stores) _storesAt = DateTime.now();
    _checkDrops(app);
    if (stores) _checkReviews();
    loading = false;
    notifyListeners();
    if (_again) {
      _again = false;
      await refresh(force: true);
    }
  }

  /// Yeni kötü yorumlar için bildirim. İlk çalışmada mevcutlar sessizce
  /// görülmüş sayılır; yoksa eski yorumlar topluca bildirim olarak gelir.
  void _checkReviews() {
    const key = 'reviews.seen';
    final first = !_prefs.containsKey(key);
    final seen = {...?_prefs.getStringList(key)};
    for (final r in lowReviews) {
      if (!seen.add(r.id) || first) continue;
      final text = r.text.isEmpty ? '(metin yok)' : r.text;
      unawaited(
        Notifier.show(
          '${appName(r)}: ${r.stars} yıldız (${r.source})',
          text,
        ).catchError((_) {}),
      );
    }
    // Liste şişmesin: son 500 kimlik yeter.
    final list = seen.toList();
    unawaited(
      _prefs.setStringList(
        key,
        list.length > 500 ? list.sublist(list.length - 500) : list,
      ),
    );
  }

  void _checkDrops(AppEntry? app) {
    final yday = ymd(DateTime.now().subtract(const Duration(days: 1)));
    final ga4 = ga4Data?.daily;
    drops = [
      // GA4'te son değer bugün (yarım gün); dünü karşılaştır.
      if (ga4 != null && ga4.length > 1)
        ?Drop.find(
          ga4.sublist(0, ga4.length - 1),
          source: 'GA4',
          metric: 'aktif kullanıcı',
          date: yday,
        ),
      for (final (name, data) in [
        ('App Store', appStoreData),
        ('Google Play', playData),
      ])
        if (data?.last case final last?)
          ?Drop.find(
            data!.values,
            source: name,
            metric: 'kurulum',
            date: last.date,
          ),
    ];
    final scope = app?.name ?? 'Tüm uygulamalar';
    for (final d in drops) {
      final key = 'drop.${app?.id ?? 'all'}.${d.source}';
      if (_prefs.getString(key) == d.date) continue;
      unawaited(_prefs.setString(key, d.date));
      unawaited(Notifier.show('$scope: düşüş', d.text).catchError((_) {}));
    }
  }

  Future<void> _refreshGa4(AppEntry? app) async {
    if (app != null && app.ga4PropertyId == null) {
      ga4Data = null;
      ga4Error = null;
      return;
    }
    try {
      ga4Data = await _fetchGa4(ga4!, ga4Settings!, app);
      ga4Error = null;
    } catch (e) {
      ga4Error = '$e';
    }
  }

  Future<void> _refreshAppStore(AppEntry? app) async {
    if (app != null && app.appleId == null) {
      appStoreData = null;
      appStoreRating = null;
      appStoreSubs = null;
      appStoreError = null;
      return;
    }
    try {
      appStoreData = await appStore!.series(appleId: app?.appleId);
      appStoreError = null;
      appStoreRating = await appStore!
          .ratings(appleId: app?.appleId)
          .catchError((_) => null);
      appStoreSubs = await appStore!
          .subscribers(appleId: app?.appleId)
          .catchError((_) => null);
    } catch (e) {
      appStoreError = '$e';
    }
  }

  Future<void> _refreshPlay(AppEntry? app) async {
    if (app != null && app.playPackage == null) {
      playData = null;
      playRating = null;
      playSubs = null;
      playError = null;
      return;
    }
    try {
      playData = await play!.series(package: app?.playPackage);
      playError = null;
      playRating = await play!
          .ratings(package: app?.playPackage)
          .catchError((_) => null);
      playSubs = await play!
          .subscribers(package: app?.playPackage)
          .catchError((_) => null);
    } catch (e) {
      playError = '$e';
    }
  }

  /// [app] seçiliyse onun mülkü ve akışları kullanılır. Mülk ayarlı mülkten
  /// farklıysa özel boyut ve ölçüler o mülkte olmayabilir; kullanılmaz.
  static Future<Ga4Snapshot> _fetchGa4(
    Ga4Client c,
    Ga4Settings settings,
    AppEntry? app,
  ) async {
    final id = app?.ga4PropertyId ?? settings.propertyId;
    final same = id == settings.propertyId;
    final s = same
        ? settings
        : Ga4Settings(propertyId: id, propertyName: app!.name);
    final streams = app?.ga4StreamIds;
    final realtime = c.realtimeActiveUsers(id, streamIds: streams);
    final daily = c.report(
      id,
      dateRanges: [
        {'startDate': '13daysAgo', 'endDate': 'today'},
      ],
      dimensions: ['date'],
      metrics: ['activeUsers', 'newUsers'],
      limit: 20,
      streamIds: streams,
    );
    final games = s.gameDimension == null
        ? Future.value(const <Map<String, String>>[])
        : c.report(
            id,
            dateRanges: [
              {'startDate': 'today', 'endDate': 'today'},
            ],
            dimensions: [s.gameDimension!],
            metrics: ['activeUsers', ?s.durationMetric, ?s.revenueMetric],
            orderByMetric: 'activeUsers',
            limit: 100,
            streamIds: streams,
          );

    final now = DateTime.now();
    String key(DateTime d) =>
        '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';
    String iso(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final yday = now.subtract(const Duration(days: 1));
    final monthStart = DateTime(now.year, now.month);
    // Ayın ilk günü dün bir önceki ayda kalır; aralık ikisini de kapsar.
    final from = yday.isBefore(monthStart) ? yday : monthStart;
    final revenueDays = s.revenueMetric == null
        ? null
        : c.report(
            id,
            dateRanges: [
              {'startDate': iso(from), 'endDate': 'today'},
            ],
            dimensions: ['date'],
            metrics: [s.revenueMetric!],
            limit: 40,
            streamIds: streams,
          );

    // D1 için 2-8 gün önceki, D7 için 8-13 gün önceki kohortlar (12 kohort).
    final cohortDays = [
      for (var i = 2; i <= 13; i++) iso(now.subtract(Duration(days: i))),
    ];
    final cohorts = c
        .cohortReport(
          id,
          cohortDays: cohortDays,
          endOffset: 7,
          streamIds: streams,
        )
        .then<List<Map<String, String>>?>((r) => r)
        .catchError((_) => null);
    // D30 için 31-42 gün önceki kohortlar; ayrı istek, hata verirse D30 boş.
    final longDays = [
      for (var i = 31; i <= 42; i++) iso(now.subtract(Duration(days: i))),
    ];
    final longCohorts = c
        .cohortReport(
          id,
          cohortDays: longDays,
          endOffset: 30,
          streamIds: streams,
        )
        .then<List<Map<String, String>>?>((r) => r)
        .catchError((_) => null);

    final days = {for (final r in await daily) r['date']!: r};
    RevenueSummary? revenue;
    if (revenueDays != null) {
      final byDay = {
        for (final r in await revenueDays)
          r['date']!: double.tryParse(r[s.revenueMetric!] ?? '') ?? 0,
      };
      final monthKey = key(monthStart);
      revenue = RevenueSummary(
        today: byDay[key(now)] ?? 0,
        yesterday: byDay[key(yday)] ?? 0,
        month: byDay.entries
            .where((e) => e.key.compareTo(monthKey) >= 0)
            .fold(0.0, (a, e) => a + e.value),
      );
    }
    int users(DateTime d) =>
        int.tryParse(days[key(d)]?['activeUsers'] ?? '') ?? 0;
    final series = [
      for (var i = 13; i >= 0; i--) users(now.subtract(Duration(days: i))),
    ];

    return Ga4Snapshot(
      realtime: await realtime,
      today: series.last,
      yesterday: series[series.length - 2],
      newToday: int.tryParse(days[key(now)]?['newUsers'] ?? '') ?? 0,
      daily: series,
      games: [
        for (final r in await games)
          if ((r[s.gameDimension!] ?? '').isNotEmpty &&
              r[s.gameDimension!] != '(not set)')
            GameRow(
              id: r[s.gameDimension!]!,
              users: int.tryParse(r['activeUsers']!) ?? 0,
              seconds: s.durationMetric == null
                  ? null
                  : double.tryParse(r[s.durationMetric!] ?? ''),
              revenue: s.revenueMetric == null
                  ? null
                  : double.tryParse(r[s.revenueMetric!] ?? ''),
            ),
      ],
      at: DateTime.now(),
      revenue: revenue,
      retention: _retention(
        await cohorts,
        cohortDays,
        await longCohorts,
        longDays,
      ),
    );
  }

  static Retention? _retention(
    List<Map<String, String>>? rows,
    List<String> cohortDays,
    List<Map<String, String>>? longRows,
    List<String> longDays,
  ) {
    if (rows == null) return null;
    final total = <String, int>{};
    final active = <String, int>{}; // "kohort|gün" → aktif
    for (final r in [...rows, ...?longRows]) {
      final c = r['cohort'] ?? '';
      final n = int.tryParse(r['cohortNthDay'] ?? '') ?? -1;
      total[c] = int.tryParse(r['cohortTotalUsers'] ?? '') ?? total[c] ?? 0;
      active['$c|$n'] = int.tryParse(r['cohortActiveUsers'] ?? '') ?? 0;
    }
    (double?, int) rate(int nth, Iterable<String> group) {
      var base = 0, back = 0;
      for (final c in group) {
        base += total[c] ?? 0;
        back += active['$c|$nth'] ?? 0;
      }
      return (base == 0 ? null : back / base, base);
    }

    // cohortDays[0] = 2 gün önce. D1: 2-8 gün önce, D7: 8-13 gün önce.
    final (d1, d1Users) = rate(1, cohortDays.sublist(0, 7));
    final (d7, d7Users) = rate(7, cohortDays.sublist(6));
    final (d30, d30Users) = longRows == null ? (null, 0) : rate(30, longDays);
    return Retention(
      d1: d1,
      d7: d7,
      d30: d30,
      d1Users: d1Users,
      d7Users: d7Users,
      d30Users: d30Users,
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    ga4?.close();
    appStore?.close();
    play?.close();
    admob?.close();
    super.dispose();
  }
}
