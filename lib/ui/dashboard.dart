import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:window_manager/legacy.dart';

import '../data/app_state.dart';
import '../data/drops.dart';
import '../data/insights.dart';
import '../data/store_series.dart';
import 'settings.dart';
import 'setup_wizard.dart';
import 'ga4_settings.dart';
import 'store_settings.dart';
import 'edge_dock.dart';
import 'logos.dart';
import 'theme.dart';

/// Kurulum sihirbazı bu oturumda kendiliğinden açıldı mı.
bool _wizardShown = false;

/// Ana pencere: üst çubuk, veri kartları ve bugünkü kırılım tablosu.
class Dashboard extends StatelessWidget {
  const Dashboard({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: Glass.window(),
        clipBehavior: Clip.antiAlias,
        child: ListenableBuilder(
          listenable: state,
          builder: (context, _) {
            void openGa4() => showGa4Settings(context, state);
            void openAppStore() => showAppStoreSettings(context, state);
            void openPlay() => showPlaySettings(context, state);
            void openAdmob() => showAdmobSettings(context, state);
            final data = state.ga4Data;
            // Gelir kartı yalnız AdMob raporundan; GA4 tahmini kullanılmaz.
            final revenue = state.admobData;
            _hideMoney = state.hideMoney;
            // İlk açılışta sihirbaz kendiliğinden gelir; oturumda bir kez.
            if (state.needsSetup && !_wizardShown) {
              _wizardShown = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (context.mounted) showSetupWizard(context, state);
              });
            }
            final storeMoney =
                (state.appStoreData?.hasRevenue ?? false) ||
                (state.playData?.hasRevenue ?? false);
            return Column(
              children: [
                _TopBar(
                  state: state,
                  onSettings: () => showSettings(context, state),
                ),
                if (state.loading)
                  const LinearProgressIndicator(minHeight: 1.5)
                else
                  const SizedBox(height: 1.5),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
                    children: [
                      if (state.needsSetup) ...[
                        _Placeholder(
                          'Başlamak için kurulum sihirbazını açın: her veri '
                          'kaynağı için ne gerektiğini adım adım gösterir.',
                          onTap: () => showSetupWizard(context, state),
                        ),
                        const SizedBox(height: 10),
                      ],
                      for (final (msg, tap) in [
                        (
                          state.ga4Error == null
                              ? null
                              : 'GA4: ${state.ga4Error}',
                          openGa4,
                        ),
                        (state.appStoreError, openAppStore),
                        (state.playError, openPlay),
                        (state.admobError, openAdmob),
                      ])
                        if (msg != null) ...[
                          _ErrorBox(msg, onTap: tap),
                          const SizedBox(height: 10),
                        ],
                      Row(
                        children: [
                          Expanded(
                            child: state.ga4Ready && data != null
                                ? _ActiveCard(data)
                                : _SourceCard(
                                    icon: Icons.people_alt_outlined,
                                    title: 'AKTİF',
                                    source: 'GA4',
                                    color: AppColors.ga4,
                                    action: state.restoring
                                        ? ''
                                        : !state.ga4Ready
                                        ? 'Bağla'
                                        : state.ga4Missing
                                        ? 'Yok'
                                        : '',
                                    loading:
                                        state.restoring ||
                                        (state.ga4Ready && !state.ga4Missing),
                                    onTap: openGa4,
                                  ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: revenue != null
                                ? _RevenueCard(
                                    revenue,
                                    appStoreSubs: state.appStoreSubs,
                                    playSubs: state.playSubs,
                                    onTap: openAdmob,
                                  )
                                : _SourceCard(
                                    icon: Icons.attach_money,
                                    title: 'REKLAM GELİRİ',
                                    source: 'AdMob',
                                    color: AppColors.admob,
                                    action: state.restoring ? '' : 'Bağla',
                                    loading: state.restoring,
                                    onTap: openAdmob,
                                  ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _InstallCard(
                              source: 'App Store',
                              color: AppColors.appStore,
                              connected: state.appStoreOn || state.restoring,
                              missing: state.appStoreMissing,
                              data: state.appStoreData,
                              summary: state.appStoreInstalls,
                              today: data?.newInstalls?['ios'],
                              rating: state.appStoreRating,
                              onTap: openAppStore,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _InstallCard(
                              source: 'Google Play',
                              color: AppColors.play,
                              connected: state.playOn || state.restoring,
                              missing: state.playMissing,
                              data: state.playData,
                              summary: state.playInstalls,
                              today: data?.newInstalls?['android'],
                              rating: state.playRating,
                              onTap: openPlay,
                            ),
                          ),
                        ],
                      ),
                      if (storeMoney) ...[
                        const SizedBox(height: 10),
                        _StoreRevenueCard(
                          appStore: state.appStoreData,
                          play: state.playData,
                        ),
                      ],
                      if (data?.retention != null) ...[
                        const SizedBox(height: 10),
                        _RetentionCard(data!.retention!),
                      ],
                      // Kırılım tablosu isteğe bağlı: GA4 bağlı ama boyut
                      // seçilmemişse bölüm hiç gösterilmez.
                      if (!state.restoring && !state.ga4Ready ||
                          state.ga4Settings?.gameDimension != null) ...[
                        const SizedBox(height: 18),
                        const _SectionTitle('KIRILIM · BUGÜN'),
                        const SizedBox(height: 8),
                        if (data == null)
                          _Placeholder(
                            'GA4 bağlanınca seçtiğiniz boyutta her satırın kullanıcı '
                            'sayısı, süresi ve geliri burada görünür.',
                            onTap: openGa4,
                          )
                        else if (data.games.isEmpty)
                          const _Placeholder('Bugün henüz veri yok.')
                        else
                          _GamesTable(
                            data.games,
                            limit: state.ga4Settings?.gameLimit ?? 5,
                          ),
                      ],
                      if (data != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          '${state.ga4Settings?.propertyName ?? ''} · '
                          'son yenileme ${_hm(data.at)}',
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

String _hm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// Ekran paylaşımı için: açıkken tüm tutarlar "•••" yazılır.
bool _hideMoney = false;

String _money(double v, [String currency = 'USD']) {
  if (_hideMoney) return '•••';
  const signs = {'USD': '\$', 'EUR': '€', 'TRY': '₺', 'GBP': '£'};
  final sign = signs[currency];
  final n = v.toStringAsFixed(v < 10 ? 2 : 0);
  return sign == null ? '$n $currency' : '$sign$n';
}

String _minutes(double s) {
  final m = s / 60;
  if (m < 60) return '${m.round()} dk';
  return '${(m / 60).toStringAsFixed(1)} sa';
}

/// Sürüklenebilir üst çubuk: uygulama seçici ve düğmeler.
class _TopBar extends StatefulWidget {
  const _TopBar({required this.state, required this.onSettings});

  final AppState state;
  final VoidCallback onSettings;

  @override
  State<_TopBar> createState() => _TopBarState();
}

class _TopBarState extends State<_TopBar> {
  bool _pinned = true;

  Future<void> _togglePin() async {
    final next = !_pinned;
    await windowManager.setAlwaysOnTop(next);
    setState(() => _pinned = next);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    return DragToMoveArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 10),
        child: Row(
          children: [
            if (s.apps.isEmpty)
              const Text(
                'APP SIGNAL',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2.2,
                  fontSize: 13,
                ),
              )
            else
              // Spacer ile yarışmasın: boş alanın tamamı seçicinin.
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _AppPicker(state: s),
                ),
              ),
            if (s.apps.isEmpty) const Spacer(),
            _BellButton(state: s),
            _BarButton(
              icon: Icons.refresh,
              tooltip: 'Yenile',
              onTap: s.anyReady && !s.loading
                  ? () => s.refresh(force: true)
                  : null,
            ),
            _BarButton(
              icon: s.hideMoney
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              tooltip: s.hideMoney ? 'Tutarları göster' : 'Tutarları gizle',
              active: s.hideMoney,
              onTap: () => s.setHideMoney(!s.hideMoney),
            ),
            _BarButton(
              icon: _pinned ? Icons.push_pin : Icons.push_pin_outlined,
              tooltip: _pinned ? 'Üstte tutma' : 'Hep üstte tut',
              active: _pinned,
              onTap: _togglePin,
            ),
            _BarButton(
              icon: Icons.settings_outlined,
              tooltip: 'GA4 ayarları',
              onTap: widget.onSettings,
            ),
            _BarButton(
              icon: Icons.close,
              tooltip: 'Gizle',
              onTap: EdgeDock.instance.slideOut,
            ),
          ],
        ),
      ),
    );
  }
}

/// Üst çubuktaki uygulama seçici: "Tüm uygulamalar" ya da tek uygulama.
class _AppPicker extends StatelessWidget {
  const _AppPicker({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final app = state.selectedApp;
    const style = TextStyle(fontWeight: FontWeight.w700, fontSize: 13);
    Widget item(AppEntry? a) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _AppIcon(state, a),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            a?.name ?? 'Tüm uygulamalar',
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
        if (a != null) ...[
          const SizedBox(width: 6),
          if (a.appleId != null)
            sourceLabel('App Store', AppColors.muted, size: 11),
          if (a.playPackage != null)
            sourceLabel('Google Play', AppColors.muted, size: 11),
          if (a.ga4PropertyId != null)
            sourceLabel('GA4', AppColors.muted, size: 11),
        ],
      ],
    );
    return PopupMenuButton<String>(
      tooltip: 'Uygulama seç',
      color: AppColors.card,
      position: PopupMenuPosition.under,
      constraints: const BoxConstraints(minWidth: 260, maxWidth: 400),
      onSelected: (id) => state.selectApp(id.isEmpty ? null : id),
      itemBuilder: (_) => [
        PopupMenuItem(value: '', height: 36, child: item(null)),
        const PopupMenuDivider(height: 6),
        for (final a in state.apps)
          PopupMenuItem(value: a.id, height: 36, child: item(a)),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _AppIcon(state, app),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                app?.name ?? 'Tüm uygulamalar',
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
            ),
            const Icon(Icons.expand_more, size: 18, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}

/// Uygulamanın mağaza ikonu; yoksa ya da "tümü" için düz bir simge.
class _AppIcon extends StatelessWidget {
  const _AppIcon(this.state, this.app);

  final AppState state;
  final AppEntry? app;

  @override
  Widget build(BuildContext context) {
    const size = 20.0;
    final url = app == null ? null : state.icons[app!.id];
    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0x1FFFFFFF),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Icon(
        app == null ? Icons.apps : Icons.videogame_asset_outlined,
        size: 13,
        color: AppColors.muted,
      ),
    );
    if (url == null) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(5),
      child: Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }
}

/// Bildirim zili: uyarı, teşhis ve kötü yorum sayısı rozette.
class _BellButton extends StatelessWidget {
  const _BellButton({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final n =
        state.drops.length +
        state.insights.where((i) => !i.good).length +
        state.lowReviews.length;
    return IconButton(
      tooltip: 'Bildirimler',
      onPressed: () => _showNotifications(context, state),
      iconSize: 17,
      visualDensity: VisualDensity.compact,
      color: n > 0 ? AppColors.signal : AppColors.muted,
      icon: Badge(
        isLabelVisible: n > 0,
        label: Text('$n'),
        child: Icon(
          n > 0
              ? Icons.notifications_active_outlined
              : Icons.notifications_none,
        ),
      ),
    );
  }
}

/// Bildirim sayfası: ani değişimler, teşhisler ve kötü yorumlar. Panel yalnız
/// rakamları gösterir; bunlar burada toplanır.
Future<void> _showNotifications(BuildContext context, AppState state) {
  return showDialog(
    context: context,
    builder: (_) => Dialog(
      backgroundColor: AppColors.card,
      insetPadding: const EdgeInsets.all(14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.cardBorder),
      ),
      child: ListenableBuilder(
        listenable: state,
        builder: (context, _) {
          final empty =
              state.drops.isEmpty &&
              state.insights.isEmpty &&
              state.lowReviews.isEmpty;
          return ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(18),
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Bildirimler',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Kapat',
                    iconSize: 17,
                    visualDensity: VisualDensity.compact,
                    color: AppColors.muted,
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              if (empty)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Şu an bakılacak bir şey yok.',
                    style: TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                ),
              for (final d in state.drops) ...[
                const SizedBox(height: 10),
                _DropBox(d, hideMoney: state.hideMoney),
              ],
              if (state.insights.isNotEmpty) ...[
                const SizedBox(height: 16),
                const _SectionTitle('BUGÜN BAKMAN GEREKEN'),
                for (final i in state.insights) ...[
                  const SizedBox(height: 8),
                  _InsightTile(i),
                ],
              ],
              if (state.lowReviews.isNotEmpty) ...[
                const SizedBox(height: 16),
                _LowReviews(state),
              ],
            ],
          );
        },
      ),
    ),
  );
}

class _BarButton extends StatelessWidget {
  const _BarButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      iconSize: 17,
      visualDensity: VisualDensity.compact,
      color: active ? AppColors.signal : AppColors.muted,
      icon: Icon(icon),
    );
  }
}

/// Kart çerçevesi: başlık satırı, gövde ve alt satır.
class _Card extends StatelessWidget {
  const _Card({
    required this.icon,
    required this.title,
    required this.color,
    required this.body,
    required this.footer,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final Color color;
  final Widget body;
  final Widget footer;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(Glass.radius),
      child: Ink(
        decoration: Glass.card(),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Glass.radius),
          child: Container(
            height: 128,
            padding: const EdgeInsets.all(14),
            decoration: Glass.glow(color),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 15, color: color),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        title,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                          color: AppColors.muted,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(child: body),
                footer,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bağlı olmayan kaynak kartı.
class _SourceCard extends StatelessWidget {
  const _SourceCard({
    required this.icon,
    required this.title,
    required this.source,
    required this.color,
    required this.action,
    this.onTap,
    this.loading = false,
  });

  final IconData icon;
  final String title;
  final String source;
  final Color color;
  final String action;
  final VoidCallback? onTap;

  /// Veri bekleniyor: tire yerine küçük dönen gösterge.
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return _Card(
      icon: icon,
      title: title,
      color: color,
      onTap: onTap,
      body: loading
          ? SizedBox(
              height: 36,
              child: Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: color,
                  ),
                ),
              ),
            )
          : const Text(
              '—',
              style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
            ),
      footer: Row(
        children: [
          sourceLabel(source, color),
          const Spacer(),
          Text(
            action,
            style: TextStyle(
              fontSize: 12,
              color: onTap == null ? AppColors.muted : AppColors.text,
              decoration: onTap == null ? null : TextDecoration.underline,
              decorationColor: AppColors.muted,
            ),
          ),
        ],
      ),
    );
  }
}

/// GA4 aktif kullanıcı kartı: anlık sayı, bugün/dün ve 14 günlük çizgi.
class _ActiveCard extends StatelessWidget {
  const _ActiveCard(this.d);

  final Ga4Snapshot d;

  @override
  Widget build(BuildContext context) {
    final diff = d.yesterday == 0
        ? null
        : ((d.today - d.yesterday) / d.yesterday * 100).round();
    return _Card(
      icon: Icons.people_alt_outlined,
      title: 'AKTİF · 30 DK',
      color: AppColors.ga4,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${d.realtime}',
            style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: SizedBox(
                height: 30,
                child: CustomPaint(painter: _Sparkline(d.daily)),
              ),
            ),
          ),
        ],
      ),
      footer: Row(
        children: [
          sourceLabel('GA4', AppColors.ga4),
          const SizedBox(width: 6),
          Text(
            'Bugün ${d.today}',
            style: const TextStyle(fontSize: 12, color: AppColors.text),
          ),
          const Spacer(),
          if (diff != null)
            Text(
              '${diff >= 0 ? '+' : ''}$diff% dün',
              style: TextStyle(
                fontSize: 12,
                color: diff >= 0 ? AppColors.signal : const Color(0xFFFF6B6B),
              ),
            ),
        ],
      ),
    );
  }
}

/// Bugünkü reklam geliri, AdMob raporundan.
class _RevenueCard extends StatelessWidget {
  const _RevenueCard(this.r, {this.appStoreSubs, this.playSubs, this.onTap});

  final RevenueSummary r;
  final int? appStoreSubs;
  final int? playSubs;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return _Card(
      icon: Icons.attach_money,
      title: 'GELİR · BUGÜN',
      color: AppColors.admob,
      onTap: onTap,
      body: Tooltip(
        message: [
          r.real ? 'AdMob raporu' : 'GA4 tahmini',
          if (appStoreSubs != null || playSubs != null)
            'Abone: App Store ${appStoreSubs ?? '—'} · '
                'Google Play ${playSubs ?? '—'}',
        ].join('\n'),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _money(r.today, r.currency),
              style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: SizedBox(
                  height: 30,
                  child: CustomPaint(
                    painter: _Sparkline(r.daily, color: AppColors.admob),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      footer: Row(
        children: [
          sourceLabel(
            r.real ? 'AdMob' : 'GA4',
            r.real ? AppColors.admob : AppColors.ga4,
          ),
          const SizedBox(width: 6),
          Text(
            'Dün ${_money(r.yesterday, r.currency)}',
            style: const TextStyle(fontSize: 12, color: AppColors.text),
          ),
          const Spacer(),
          Text(
            'Ay ${_money(r.month, r.currency)}',
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

/// Yeni kullanıcıların D1, D7 ve D30 dönme oranı (GA4 kohort raporu).
class _RetentionCard extends StatelessWidget {
  const _RetentionCard(this.r);

  final Retention r;

  @override
  Widget build(BuildContext context) {
    String pct(double? v) => v == null ? '—' : '%${(v * 100).round()}';
    Widget cell(String label, double? v, int users) => Expanded(
      child: Tooltip(
        message: '$users yeni kullanıcı üzerinden',
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              pct(v),
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          ],
        ),
      ),
    );
    return _Card(
      icon: Icons.replay,
      title: 'TUTUNMA · YENİ KULLANICI',
      color: AppColors.ga4,
      body: Row(
        children: [
          cell('D1', r.d1, r.d1Users),
          cell('D7', r.d7, r.d7Users),
          cell('D30', r.d30, r.d30Users),
        ],
      ),
      footer: const SizedBox.shrink(),
    );
  }
}

/// Mağaza kurulum kartı: yayından bu yana toplam, bugünkü yeni kurulum
/// (GA4 first_open) ve en son raporlanan günün silmesi.
class _InstallCard extends StatelessWidget {
  const _InstallCard({
    required this.source,
    required this.color,
    required this.connected,
    this.missing = false,
    required this.data,
    required this.onTap,
    this.summary,
    this.today,
    this.rating,
  });

  final RatingSummary? rating;
  final String source;
  final Color color;
  final bool connected;
  final bool missing;

  /// Mağaza verisi geldi mi; gelene kadar kart yükleniyor görünür.
  final StoreSeries? data;
  final InstallSummary? summary;

  /// Bugünkü yeni kurulum; GA4 bağlı değilse null.
  final int? today;
  final VoidCallback onTap;

  /// 12345 → "12.345".
  static String _n(int? v) {
    if (v == null) return '—';
    final s = v.abs().toString();
    final b = StringBuffer(v < 0 ? '-' : '');
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
      b.write(s[i]);
    }
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    final d = data;
    if (!connected || missing || d == null) {
      return _SourceCard(
        icon: Icons.download_outlined,
        title: 'KURULUM',
        source: source,
        color: color,
        action: !connected
            ? 'Bağla'
            : missing
            ? 'Yok'
            : '',
        loading: connected && !missing,
        onTap: onTap,
      );
    }
    final s = summary;
    final delDate = s?.deletesDate;
    final all = d.values;
    final spark = all.length > 14 ? all.sublist(all.length - 14) : all;
    // Sağ sütunda küçük satır: "+4 bugün", "−2 silme".
    Widget line(String sign, int? v, String label, Color c, String tip) =>
        Tooltip(
          message: tip,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                v == null ? '—' : '$sign${_n(v)}',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: v == null ? AppColors.muted : c,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ],
          ),
        );
    return _Card(
      icon: Icons.download_outlined,
      title: 'KURULUM',
      color: color,
      onTap: onTap,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Tooltip(
                  message: s?.total == null ? 'Toplam kurulum okunamadı.' : 'Yayından bu yana mağaza raporlarındaki toplam kurulum.',
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      _n(s?.total),
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                // Son 14 raporlu günün kurulumu.
                Expanded(
                  child: SizedBox(
                    width: double.infinity,
                    child: CustomPaint(
                      painter: _Sparkline(spark, color: color),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                line(
                  '+',
                  today,
                  'bugün',
                  AppColors.text,
                  today == null
                      ? 'Bugünkü kurulum GA4 first_open olayından gelir; bu '
                            'platformda GA4 verisi yok.'
                      : 'GA4 first_open: bugün uygulamayı ilk kez açanlar. '
                            'Gün henüz bitmedi.',
                ),
                const SizedBox(height: 2),
                line(
                  '−',
                  s?.deletes,
                  'silme',
                  AppColors.muted,
                  s?.deletes == null || delDate == null
                      ? (s?.note ?? 'Silme sayısı okunamadı.')
                      : '${StoreDay(delDate, 0).short} günü silinen kurulum '
                            '(mağazanın en son raporladığı gün).',
                ),
              ],
            ),
          ),
        ],
      ),
      footer: Row(
        children: [
          sourceLabel(source, color),
          if ((rating?.total ?? rating?.average) != null)
            Tooltip(
              message: [
                if (rating!.total != null)
                  rating!.totalCount == null
                      ? 'Mağazadaki genel puan'
                      : 'Mağazadaki genel puan, ${_n(rating!.totalCount)} oy',
                if (rating!.average != null)
                  'Son 30 gün: ★${rating!.average!.toStringAsFixed(1)} '
                      '(${rating!.count} yorum)',
              ].join('\n'),
              child: Text(
                ' ★${(rating!.total ?? rating!.average)!.toStringAsFixed(1)}'
                '${rating!.totalCount == null ? '' : ' (${_n(rating!.totalCount)})'}',
                style: const TextStyle(fontSize: 12, color: Color(0xFFFFC857)),
              ),
            ),
        ],
      ),
    );
  }
}

class _Sparkline extends CustomPainter {
  _Sparkline(this.values, {this.color = AppColors.ga4});

  final List<num> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final top = values.fold<num>(0, math.max).toDouble();
    if (top == 0) return;
    final dx = size.width / (values.length - 1);
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final p = Offset(i * dx, size.height - values[i] / top * size.height);
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    final area = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.35), color.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    final end = Offset(
      size.width,
      size.height - values.last / top * size.height,
    );
    canvas.drawCircle(
      end,
      5,
      Paint()
        ..color = color.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawCircle(end, 2.4, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_Sparkline old) =>
      old.values != values || old.color != color;
}

class _GamesTable extends StatelessWidget {
  const _GamesTable(this.games, {required this.limit});

  final List<GameRow> games;

  /// En çok kaç satır gösterilir; 0 hepsi.
  final int limit;

  @override
  Widget build(BuildContext context) {
    final showTime = games.any((g) => g.seconds != null);
    final showRev = games.any((g) => g.revenue != null);
    const head = TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.w700,
      letterSpacing: 1,
      color: AppColors.muted,
    );
    Widget row(
      String name,
      String users,
      String? time,
      String? rev, {
      TextStyle? style,
    }) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Text(name, overflow: TextOverflow.ellipsis, style: style),
            ),
            SizedBox(
              width: 52,
              child: Text(users, textAlign: TextAlign.right, style: style),
            ),
            if (time != null)
              SizedBox(
                width: 62,
                child: Text(time, textAlign: TextAlign.right, style: style),
              ),
            if (rev != null)
              SizedBox(
                width: 62,
                child: Text(rev, textAlign: TextAlign.right, style: style),
              ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      decoration: Glass.card(),
      child: Column(
        children: [
          row(
            'AD',
            'KİŞİ',
            showTime ? 'SÜRE' : null,
            showRev ? 'GELİR' : null,
            style: head,
          ),
          const Divider(height: 1, color: Color(0x1AFFFFFF)),
          for (final g in limit > 0 ? games.take(limit) : games)
            row(
              g.id,
              '${g.users}',
              showTime
                  ? (g.seconds == null ? '—' : _minutes(g.seconds!))
                  : null,
              showRev ? (g.revenue == null ? '—' : _money(g.revenue!)) : null,
              style: const TextStyle(fontSize: 13),
            ),
          if (limit > 0 && games.length > limit)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 2),
              child: Text(
                '+${games.length - limit} satır daha',
                style: const TextStyle(fontSize: 11, color: AppColors.muted),
              ),
            ),
        ],
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox(this.message, {required this.onTap});

  final String message;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0x22FF6B6B),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            message,
            style: const TextStyle(color: Color(0xFFFF9B9B), fontSize: 12),
          ),
        ),
      ),
    );
  }
}

/// Son 7 günün 1-2 yıldızlı yorumları.
class _LowReviews extends StatelessWidget {
  const _LowReviews(this.state);

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final all = state.lowReviews;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: Glass.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle('KÖTÜ YORUMLAR · 7 GÜN · ${all.length}'),
          for (final r in all) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Text(
                  '★' * r.stars + '☆' * (5 - r.stars),
                  style: const TextStyle(
                    color: Color(0xFFFFB86B),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${state.appName(r)} · ${r.source}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 11,
                    ),
                  ),
                ),
                Text(
                  '${r.at.day}.${r.at.month.toString().padLeft(2, '0')}',
                  style: const TextStyle(color: AppColors.muted, fontSize: 11),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              r.text.isEmpty ? '(metin yok)' : r.text,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, height: 1.35),
            ),
          ],
        ],
      ),
    );
  }
}

/// Düşüş uyarısı turuncu şerit ve aşağı ok; sıçrama yeşil şerit, yukarı ok.
class _DropBox extends StatelessWidget {
  const _DropBox(this.drop, {this.hideMoney = false});

  final Drop drop;
  final bool hideMoney;

  @override
  Widget build(BuildContext context) {
    final up = drop.up;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: up ? const Color(0x2235D07F) : const Color(0x22FFA94D),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            up ? Icons.trending_up : Icons.trending_down,
            size: 16,
            color: up ? const Color(0xFF5BE09A) : const Color(0xFFFFB86B),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              drop.textFor(hideMoney: hideMoney),
              style: TextStyle(
                color: up ? const Color(0xFF8FEBB9) : const Color(0xFFFFC48A),
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Mağaza net geliri (USD): App Store raporu ve Play tahmini yan yana.
class _StoreRevenueCard extends StatelessWidget {
  const _StoreRevenueCard({this.appStore, this.play});

  final StoreSeries? appStore;
  final StoreSeries? play;

  @override
  Widget build(BuildContext context) {
    Widget cell(String source, StoreSeries? d) {
      final last = d?.lastRevenue;
      final known = d != null && d.hasRevenue;
      return Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              known ? _money(d.monthRevenue ?? 0) : '—',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                ?sourceLogo(source, size: 12),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    known
                        ? 'bu ay · ${last!.short} ${_money(last.revenue ?? 0)}'
                        : 'izin yok',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.muted,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return _Card(
      icon: Icons.storefront_outlined,
      title: 'MAĞAZA GELİRİ · NET',
      color: AppColors.appStore,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          cell('App Store', appStore),
          const SizedBox(width: 12),
          cell('Google Play', play),
          const Tooltip(
            message:
                'USD, ayın başından son raporlanan güne kadar; altında son '
                'günün geliri. App Store: raporlanan net gelir. Google Play: vergisiz '
                'fiyatın %85\'i (tahmini). Kurlar open.er-api.com\'dan.',
            child: Icon(Icons.info_outline, size: 14, color: AppColors.muted),
          ),
        ],
      ),
      footer: const SizedBox.shrink(),
    );
  }
}

/// Teşhis: başlık, neden ve ne yapılmalı.
class _InsightTile extends StatelessWidget {
  const _InsightTile(this.insight);

  final Insight insight;

  @override
  Widget build(BuildContext context) {
    final good = insight.good;
    final color = good ? const Color(0xFF5BE09A) : const Color(0xFFFFB86B);
    Widget line(String label, String text) => Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label  ',
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
                color: AppColors.muted,
              ),
            ),
            TextSpan(text: text),
          ],
        ),
        style: const TextStyle(fontSize: 12, height: 1.35),
      ),
    );
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: Glass.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                good ? Icons.check_circle_outline : Icons.error_outline,
                size: 15,
                color: color,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  insight.title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          line('NEDEN', insight.why),
          line('NE YAP', insight.todo),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.4,
        color: AppColors.muted,
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder(this.text, {this.onTap});

  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(Glass.radius),
      child: Ink(
        decoration: Glass.card(),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Glass.radius),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Text(
              text,
              style: const TextStyle(color: AppColors.muted, height: 1.4),
            ),
          ),
        ),
      ),
    );
  }
}
