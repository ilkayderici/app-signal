import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Veri kaynaklarının küçük logoları; varlık dosyası gerektirmeden çizilir.
/// Tanınmayan kaynak için null döner, çağıran metin gösterir.
Widget? sourceLogo(String source, {double size = 15}) {
  final icon = switch (source) {
    'App Store' => (Icons.apple, const Color(0xFFE6EAF0)),
    'Google Play' || 'Play' => (Icons.android, const Color(0xFF3DDC84)),
    _ => null,
  };
  if (source == 'AdMob') {
    return Tooltip(
      message: source,
      child: SvgPicture.string(_admobSvg, width: size + 1, height: size + 1),
    );
  }
  if (icon != null) {
    return Tooltip(
      message: source,
      child: Icon(icon.$1, size: size + 2, color: icon.$2),
    );
  }
  final CustomPainter? painter = switch (source) {
    'GA4' => _Ga4Painter(),
    _ => null,
  };
  if (painter == null) return null;
  return Tooltip(
    message: source,
    child: SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: painter),
    ),
  );
}

/// Logo, yoksa kaynağın adı.
Widget sourceLabel(String source, Color color, {double size = 15}) =>
    sourceLogo(source, size: size) ??
    Text(source, style: TextStyle(fontSize: 12, color: color));

/// Analytics çubukları: nokta, orta ve uzun çubuk.
class _Ga4Painter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    final bw = w * 0.28;
    RRect bar(double x, double top) =>
        RRect.fromLTRBR(x, top, x + bw, h, Radius.circular(bw / 2));
    canvas.drawRRect(
      bar(w * 0.72, 0),
      Paint()..color = const Color(0xFFF9AB00),
    );
    canvas.drawRRect(
      bar(w * 0.36, h * 0.36),
      Paint()..color = const Color(0xFFE37400),
    );
    canvas.drawCircle(
      Offset(bw / 2, h - bw / 2),
      bw / 2,
      Paint()..color = const Color(0xFFE37400),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// Google'ın resmi AdMob işareti (yazısız kısmı).
const _admobSvg =
    '<svg viewBox="6 2 37 37" xmlns="http://www.w3.org/2000/svg">'
    '<path d="M23.728 3.596c.482-.044.965-.061 1.449-.053 8.836.325 15.932 7.402 16.28 16.238v13.33a4.377 4.377 0 0 1-4.388 4.346 4.863 4.863 0 0 1-4.09-4.335v-13.33a8.457 8.457 0 0 0-9.25-7.76" fill="#FBBC04"/>'
    '<path d="M41.457 33.217a4.229 4.229 0 1 1-8.458 0 4.229 4.229 0 0 1 8.458 0z" fill="#4285F4"/>'
    '<path d="M23.971 37.309a4.345 4.345 0 0 0 4.398-4.314 4.229 4.229 0 0 0-4.45-4.101 8.457 8.457 0 0 1-7.792-9.007v-.074a8.51 8.51 0 0 1 7.844-7.791 4.229 4.229 0 0 0 4.398-4.123 4.355 4.355 0 0 0-4.398-4.313h-.296c-8.99.416-16.08 7.798-16.132 16.798v.063c0 10.572 9.272 16.862 16.175 16.862h.253z" fill="#EA4335"/>'
    '</svg>';
