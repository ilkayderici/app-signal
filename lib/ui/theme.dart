import 'dart:io';

import 'package:flutter/material.dart';

/// Renkler tek yerde. Koyu, sade; her veri kaynağının kendi vurgu rengi var.
abstract final class AppColors {
  static const background = Color(0xFF0E1116);
  static const card = Color(0xFF161B22);
  static const cardBorder = Color(0xFF262D36);
  static const text = Color(0xFFE6EAF0);
  static const muted = Color(0xFF8B95A3);
  static const signal = Color(0xFF3DDC97);

  static const ga4 = Color(0xFFF5A623);
  static const admob = Color(0xFF4C8DFF);
  static const appStore = Color(0xFF5AC8FA);
  static const play = Color(0xFF34C759);
}

/// Cam görünüm: üstten aşağı sönen beyaz parlaklık ve ince açık kenar.
abstract final class Glass {
  static const radius = 12.0;

  /// Pencere zemini: Mac'te arkadaki bulanıklık hafif görünsün diye yarı
  /// saydam. Windows'ta bulanıklık yok; zemin opak, köşeyi DWM yuvarlar.
  static BoxDecoration window() => Platform.isWindows
      ? const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF141A24), Color(0xFF090B10)],
          ),
        )
      : BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xA6141A24), Color(0xCC090B10)],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0x24FFFFFF)),
        );

  /// Kart yüzeyi.
  static BoxDecoration card({double r = radius}) => BoxDecoration(
    gradient: const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0x1FFFFFFF), Color(0x08FFFFFF)],
    ),
    borderRadius: BorderRadius.circular(r),
    border: Border.all(color: const Color(0x1FFFFFFF)),
    boxShadow: const [
      BoxShadow(color: Color(0x40000000), blurRadius: 14, offset: Offset(0, 6)),
    ],
  );

  /// Kartın sol üstüne kaynağın rengiyle yumuşak ışık.
  static BoxDecoration glow(Color accent, {double r = radius}) => BoxDecoration(
    borderRadius: BorderRadius.circular(r),
    gradient: RadialGradient(
      center: const Alignment(-1, -1.2),
      radius: 1.3,
      colors: [accent.withValues(alpha: 0.22), accent.withValues(alpha: 0)],
    ),
  );
}

ThemeData buildTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: Colors.transparent,
    colorScheme: base.colorScheme.copyWith(
      primary: AppColors.signal,
      surface: AppColors.card,
    ),
    textTheme: base.textTheme.apply(
      bodyColor: AppColors.text,
      displayColor: AppColors.text,
    ),
  );
}
