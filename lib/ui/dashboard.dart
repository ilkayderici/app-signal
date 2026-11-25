import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:window_manager/legacy.dart';

import '../data/app_state.dart';
import '../data/store_series.dart';
import 'settings.dart';
import 'ga4_settings.dart';
import 'store_settings.dart';
import 'edge_dock.dart';
import 'logos.dart';
import 'theme.dart';

/// Ana pencere: üst çubuk, veri kartları ve bugünkü oyun listesi.
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
            final revenue = state.admobData ?? data?.revenue;
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
                      for (final d in state.drops) ...[
                        _DropBox(d.text),
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
                              rating: state.playRating,
                              onTap: openPlay,
                            ),
                          ),
                        ],
                      ),
                      if (state.lowReviews.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        _LowReviews(state),
                      ],
                      if (data?.retention != null) ...[
                        const SizedBox(height: 10),
                        _RetentionCard(
                          data!.retention!,
                          newToday: data.newToday,
                        ),
                      ],
                      // Oyun kırılımı isteğe bağlı: GA4 bağlı ama boyut
                      // seçilmemişse bölüm hiç gösterilmez.
                      if (!state.restoring && !state.ga4Ready ||
                          state.ga4Settings?.gameDimension != null) ...[
                        const SizedBox(height: 18),
                        const _SectionTitle('OYUNLAR · BUGÜN'),
                        const SizedBox(height: 8),
                        if (data == null)
                          _Placeholder(
                            'GA4 bağlanınca her oyunun oyuncu sayısı, '
                            'süresi ve geliri burada görünür.',
                            onTap: openGa4,
                          )
                        else if (data.games.isEmpty)
                          const _Placeholder('Bugün henüz oyun verisi yok.')
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

String _money(double v, [String currency = 'USD']) {
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
            _BarButton(
              icon: Icons.refresh,
              tooltip: 'Yenile',
              onTap: s.anyReady && !s.loading
                  ? () => s.refresh(force: true)
                  : null,
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

/// Bugünkü toplam gelir: AdMob bağlıysa raporundan, yoksa GA4 gelir
/// ölçüsünden (tahmini).
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
        child: Text(
          _money(r.today, r.currency),
          style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
        ),
      ),
      footer: Row(
        children: [
          sourceLabel('AdMob', AppColors.ga4),
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

/// Kaynak logosu ve yanında kısa not ("tahmini", "tutunma").
class _LogoNote extends StatelessWidget {
  const _LogoNote(this.source, this.note);

  final String source;
  final String note;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      sourceLabel(source, AppColors.ga4),
      const SizedBox(width: 6),
      Text(note, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
    ],
  );
}

/// Yeni oyuncuların D1, D7 ve D30 dönme oranı (GA4 kohort raporu).
class _RetentionCard extends StatelessWidget {
  const _RetentionCard(this.r, {required this.newToday});

  final Retention r;
  final int newToday;

  @override
  Widget build(BuildContext context) {
    String pct(double? v) => v == null ? '—' : '%${(v * 100).round()}';
    Widget cell(String label, double? v, int users) => Expanded(
      child: Tooltip(
        message: '$users yeni oyuncu üzerinden',
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
      title: 'TUTUNMA · YENİ OYUNCU',
      color: AppColors.ga4,
      body: Row(
        children: [
          cell('D1', r.d1, r.d1Users),
          cell('D7', r.d7, r.d7Users),
          cell('D30', r.d30, r.d30Users),
        ],
      ),
      footer: Row(
        children: [
          const _LogoNote('GA4', 'Tutunma'),
          const Spacer(),
          Text(
            'Bugün yeni $newToday',
            style: const TextStyle(fontSize: 12, color: AppColors.text),
          ),
        ],
      ),
    );
  }
}

/// Mağaza kurulum kartı: son raporlu gün, 7 günlük toplam ve çizgi.
class _InstallCard extends StatelessWidget {
  const _InstallCard({
    required this.source,
    required this.color,
    required this.connected,
    this.missing = false,
    required this.data,
    required this.onTap,
    this.rating,
  });

  final RatingSummary? rating;
  final String source;
  final Color color;
  final bool connected;
  final bool missing;
  final StoreSeries? data;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final d = data;
    final last = d?.last;
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
    return _Card(
      icon: Icons.download_outlined,
      title: last == null ? 'KURULUM' : 'KURULUM · ${last.short}',
      color: color,
      onTap: onTap,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            last == null ? '—' : '${last.count}',
            style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: SizedBox(
                height: 30,
                child: CustomPaint(painter: _Sparkline(d.values, color: color)),
              ),
            ),
          ),
        ],
      ),
      footer: Row(
        children: [
          sourceLabel(source, color),
          if (rating?.average != null)
            Tooltip(
              message: 'Son yorumların ortalaması (${rating!.count} yorum)',
              child: Text(
                ' ★${rating!.average!.toStringAsFixed(1)}',
                style: const TextStyle(fontSize: 12, color: Color(0xFFFFC857)),
              ),
            ),
          const Spacer(),
          Text(
            '7g ${d.week}',
            style: const TextStyle(fontSize: 12, color: AppColors.text),
          ),
        ],
      ),
    );
  }
}

class _Sparkline extends CustomPainter {
  _Sparkline(this.values, {this.color = AppColors.ga4});

  final List<int> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final top = values.reduce(math.max).toDouble();
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
  bool shouldRepaint(_Sparkline old) => old.values != values;
}

class _GamesTable extends StatelessWidget {
  const _GamesTable(this.games, {required this.limit});

  final List<GameRow> games;

  /// En çok kaç oyun gösterilir; 0 hepsi.
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
            'OYUN',
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
                '+${games.length - limit} oyun daha',
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

/// Son 7 günün 1-2 yıldızlı yorumları (en yeni 3 tanesi).
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
          for (final r in all.take(3)) ...[
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

/// Düşüş uyarısı: turuncu şerit, aşağı ok.
class _DropBox extends StatelessWidget {
  const _DropBox(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0x22FFA94D),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.trending_down, size: 16, color: Color(0xFFFFB86B)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Color(0xFFFFC48A), fontSize: 12),
            ),
          ),
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
