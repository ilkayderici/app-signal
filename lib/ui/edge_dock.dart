import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:window_manager/legacy.dart';

/// Pencereyi ana ekranın sağ üstüne yerleştirir. Pencere gizliyken imleç
/// sağ kenarın üst bölümünde kısa bir süre durursa pencere sağdan kayarak
/// gelir; kenardan açıldıysa imleç pencereden çıkınca geri kayar.
class EdgeDock {
  EdgeDock._();

  static final instance = EdgeDock._();

  static const _channel = MethodChannel('app_signal/screen');
  static const _margin = 8.0;
  static const _dwell = Duration(milliseconds: 250);
  static const _leaveDelay = Duration(milliseconds: 700);

  /// Açık bir iletişim kutusu varken pencere kendiliğinden gizlenmez.
  final navigatorKey = GlobalKey<NavigatorState>();

  Timer? _poll;
  DateTime? _edgeSince;
  DateTime? _outsideSince;
  bool _visible = false;
  bool _animating = false;
  bool _autoHide = false;

  /// Ekran kanalı (`app_signal/screen`) macOS ve Windows runner'ında var.
  bool get _supported => Platform.isMacOS || Platform.isWindows;

  Future<Rect?> _screen() async {
    final f = await _channel.invokeListMethod<double>('visibleFrame');
    return f == null ? null : Rect.fromLTWH(f[0], f[1], f[2], f[3]);
  }

  Future<Offset?> _cursor() async {
    final p = await _channel.invokeListMethod<double>('cursor');
    return p == null ? null : Offset(p[0], p[1]);
  }

  /// İlk açılış: sağ üstte göster ve kenarı izlemeye başla.
  Future<void> start() async {
    if (!_supported) {
      await windowManager.show();
      return;
    }
    final s = await _screen();
    if (s != null) {
      final size = await _fit(s);
      await windowManager.setPosition(
        Offset(s.right - size.width - _margin, s.top + _margin),
      );
    }
    await windowManager.show();
    await windowManager.focus();
    _visible = true;
    _poll = Timer.periodic(const Duration(milliseconds: 120), (_) => _tick());
  }

  Future<void> _tick() async {
    if (_animating) return;
    final s = await _screen();
    final c = await _cursor();
    if (s == null || c == null) return;
    final now = DateTime.now();

    // Gizli ya da başka pencerelerin arkasında kaldıysa kenar onu getirir.
    final front = _visible && await windowManager.isFocused();
    if (!front) {
      final size = await windowManager.getSize();
      final atEdge =
          c.dx >= s.right - 2 &&
          c.dy >= s.top &&
          c.dy <= s.top + _margin + size.height;
      if (!atEdge) {
        _edgeSince = null;
      } else if (_edgeSince == null) {
        _edgeSince = now;
      } else if (now.difference(_edgeSince!) >= _dwell) {
        _edgeSince = null;
        if (_visible) {
          await _bringToFront();
        } else {
          await slideIn(autoHide: true);
        }
      }
      return;
    }
    _edgeSince = null;

    if (!_autoHide) return;
    final pos = await windowManager.getPosition();
    final size = await windowManager.getSize();
    final inside = (pos & size).inflate(4).contains(c);
    final dialogOpen = navigatorKey.currentState?.canPop() ?? false;
    if (inside || dialogOpen) {
      _outsideSince = null;
    } else if (_outsideSince == null) {
      _outsideSince = now;
    } else if (now.difference(_outsideSince!) >= _leaveDelay) {
      _outsideSince = null;
      await slideOut();
    }
  }

  /// Sağdan kayarak sağ üste gelir. [autoHide] ise imleç çıkınca geri kayar.
  Future<void> slideIn({bool autoHide = false}) async {
    _autoHide = autoHide;
    if (!_supported) {
      await windowManager.show();
      await windowManager.focus();
      return;
    }
    if (_visible || _animating) return;
    final s = await _screen();
    if (s == null) return;
    final size = await _fit(s);
    final y = s.top + _margin;
    final to = s.right - size.width - _margin;
    _animating = true;
    await windowManager.setPosition(Offset(s.right, y));
    await windowManager.show();
    await _animate(s.right, to, y);
    await windowManager.focus();
    _visible = true;
    _outsideSince = null;
    _animating = false;
  }

  /// Sağa kayıp gizlenir.
  Future<void> slideOut() async {
    if (!_supported) {
      await windowManager.hide();
      return;
    }
    if (!_visible || _animating) return;
    final s = await _screen();
    _animating = true;
    if (s != null) {
      final pos = await windowManager.getPosition();
      await _animate(pos.dx, s.right, pos.dy);
    }
    await windowManager.hide();
    _visible = false;
    _autoHide = false;
    _animating = false;
  }

  /// Pencere ekranın kullanılabilir yüksekliği kadar uzar (üst-alt boşluklu).
  Future<Size> _fit(Rect s) async {
    final width = (await windowManager.getSize()).width;
    final size = Size(width, s.height - _margin * 2);
    await windowManager.setSize(size);
    return size;
  }

  /// Menü simgesi: önde ise gizler, gizli ya da arkada ise öne getirir.
  Future<void> toggle() async {
    if (!_visible) return slideIn();
    if (await windowManager.isFocused()) return slideOut();
    await _bringToFront();
  }

  Future<void> _bringToFront() async {
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> _animate(double from, double to, double y) async {
    const steps = 12;
    for (var i = 1; i <= steps; i++) {
      final t = Curves.easeOutCubic.transform(i / steps);
      await windowManager.setPosition(Offset(from + (to - from) * t, y));
      await Future<void>.delayed(const Duration(milliseconds: 14));
    }
  }

  void dispose() => _poll?.cancel();
}
