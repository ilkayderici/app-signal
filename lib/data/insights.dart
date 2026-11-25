import 'app_state.dart';

enum InsightKind { problem, good }

/// Kendi verimizden çıkan bir teşhis: ne oldu, neden, ne yapılmalı.
class Insight {
  const Insight(this.kind, this.title, {required this.why, required this.todo});

  final InsightKind kind;
  final String title;
  final String why;
  final String todo;

  bool get good => kind == InsightKind.good;
}

/// Seçili uygulama için kurallar. Sorunlar önce gelir, en çok [max] tane.
List<Insight> diagnose(AppState s, {int max = 4}) {
  final out = <Insight>[];
  String usd(double v) =>
      s.hideMoney ? '•••' : '\$${v.toStringAsFixed(v >= 100 ? 0 : 2)}';
  String pct(double v) => '%${(v * 100).round()}';

  final stores = [
    if (s.appStoreData case final d?) ('App Store', d),
    if (s.playData case final d?) ('Google Play', d),
  ];
  final week = stores.fold(0, (a, e) => a + e.$2.week);
  final prevs = [for (final e in stores) e.$2.prevWeek];
  final prev = prevs.contains(null) || prevs.isEmpty
      ? null
      : prevs.fold(0, (a, b) => a + b!);
  final withRevenue = [for (final e in stores) if (e.$2.hasRevenue) e.$2];
  final revenue = withRevenue.isEmpty
      ? null
      : withRevenue.fold<double>(0, (a, d) => a + (d.weekRevenue ?? 0));
  final revenuePrev = withRevenue.isEmpty ||
          withRevenue.any((d) => d.prevWeekRevenue == null)
      ? null
      : withRevenue.fold<double>(0, (a, d) => a + d.prevWeekRevenue!);
  final fullWeek = stores.isNotEmpty && stores.every((e) => e.$2.days.length >= 7);

  // Kurulum var, gelir yok.
  final ads = s.admobData?.month ?? 0;
  if (revenue != null && revenue <= 0 && week >= 50 && ads <= 0) {
    out.add(
      Insight(
        InsightKind.problem,
        'Haftada $week kurulum var ama satış yok',
        why:
            'Son 7 günün mağaza raporunda net gelir görünmüyor. Kullanıcılar '
            'ödeme ekranına ulaşmıyor ya da orada ikna olmuyor.',
        todo:
            'Ödeme ekranının ne zaman açıldığına bak. İlk oturumda göster; '
            'deneme süresi ya da daha düşük bir fiyat dene.',
      ),
    );
  }

  // Kurulanlar dönmüyor: günlük aktif / günlük kurulum.
  final daily = s.ga4Missing ? null : s.ga4Data?.daily;
  if (daily != null && daily.length >= 8 && fullWeek && week >= 35) {
    final last7 = daily.sublist(daily.length - 8, daily.length - 1);
    final dau = last7.reduce((a, b) => a + b) / 7;
    final ratio = dau / (week / 7);
    if (ratio < 1.5) {
      out.add(
        Insight(
          InsightKind.problem,
          'Kurulanlar geri gelmiyor',
          why:
              'Günlük aktif kullanıcı, günlük kurulumun yalnız '
              '${ratio.toStringAsFixed(1).replaceFirst('.', ',')} katı. '
              'Kurulanların çoğu ilk günden sonra uygulamayı açmıyor.',
          todo:
              'İlk açılışı kısalt, ilk dakikada asıl özelliği göster. Ertesi '
              'gün için bir hatırlatma bildirimi ekle.',
        ),
      );
    }
  }

  // 1. gün tutma.
  final ret = s.ga4Missing ? null : s.ga4Data?.retention;
  if (ret?.d1 case final d1? when ret!.d1Users >= 50) {
    if (d1 < 0.25) {
      out.add(
        Insight(
          InsightKind.problem,
          '1. gün tutma düşük: ${pct(d1)}',
          why:
              'Çoğu uygulamada ölçüt %25-40. Yeni kullanıcıların dörtte üçü '
              'ertesi gün dönmüyor.',
          todo:
              'Karşılama adımlarını azalt, izin isteklerini ertele. Kullanıcı '
              'ilk oturumda bir işi bitirebilmeli.',
        ),
      );
    } else if (d1 >= 0.45) {
      out.add(
        Insight(
          InsightKind.good,
          '1. gün tutma güçlü: ${pct(d1)}',
          why: 'Ölçütün (%25-40) üstünde; ürün ilk gün işini görüyor.',
          todo:
              'Edinmeyi artırmanın zamanı: mağaza sayfasını güçlendir, küçük '
              'bir reklam bütçesi dene.',
        ),
      );
    }
  }

  // Görünürlük.
  if (fullWeek && week < 10) {
    out.add(
      Insight(
        InsightKind.problem,
        'Mağazada görünmüyorsun: haftada $week kurulum',
        why:
            'Son 7 günde çok az kişi uygulamayı buldu. Sorun büyük olasılıkla '
            'üründe değil, keşfedilmede.',
        todo:
            'Başlık, alt başlık ve anahtar kelimeleri gözden geçir. İlk iki '
            'ekran görüntüsünü yenile.',
      ),
    );
  }

  // Haftalık değişim: kurulum.
  if (prev != null && prev >= 20 && fullWeek) {
    final change = week / prev - 1;
    if (change <= -0.3) {
      out.add(
        Insight(
          InsightKind.problem,
          'Kurulumlar geçen haftaya göre ${pct(-change)} düştü',
          why: 'Bu hafta $week, geçen hafta $prev kurulum.',
          todo:
              'Sıralamada, öne çıkarmada ya da reklam bütçesinde değişiklik var '
              'mı bak. Yeni sürüm çıktıysa mağaza sayfasını kontrol et.',
        ),
      );
    } else if (change >= 0.3) {
      out.add(
        Insight(
          InsightKind.good,
          'Kurulumlar geçen haftaya göre ${pct(change)} arttı',
          why: 'Bu hafta $week, geçen hafta $prev kurulum.',
          todo:
              'Neyin işe yaradığını bul (ülke, kaynak, sürüm) ve onu büyüt.',
        ),
      );
    }
  }

  // Haftalık değişim: gelir.
  if (revenue != null && revenuePrev != null && revenuePrev >= 20) {
    final change = revenue / revenuePrev - 1;
    if (change <= -0.3) {
      out.add(
        Insight(
          InsightKind.problem,
          'Mağaza geliri ${pct(-change)} düştü',
          why:
              'Bu hafta ${usd(revenue)}, geçen hafta ${usd(revenuePrev)} net '
              'gelir.',
          todo:
              'İade ve iptallere bak. Fiyat ya da ödeme ekranı değiştiyse '
              'eskisiyle karşılaştır.',
        ),
      );
    } else if (change >= 0.3) {
      out.add(
        Insight(
          InsightKind.good,
          'Mağaza geliri ${pct(change)} arttı',
          why:
              'Bu hafta ${usd(revenue)}, geçen hafta ${usd(revenuePrev)} net '
              'gelir.',
          todo: 'Artışın hangi üründen geldiğini bul; o ürünü öne çıkar.',
        ),
      );
    }
  }

  // Yorumlar.
  final dayAgo = DateTime.now().subtract(const Duration(hours: 24));
  final fresh = s.lowReviews.where((r) => r.at.isAfter(dayAgo)).toList();
  if (fresh.length >= 2) {
    final sample = fresh.firstWhere(
      (r) => r.text.isNotEmpty,
      orElse: () => fresh.first,
    );
    final quote = sample.text.length > 90
        ? '${sample.text.substring(0, 90)}…'
        : sample.text;
    out.add(
      Insight(
        InsightKind.problem,
        'Son 24 saatte ${fresh.length} kötü yorum',
        why: quote.isEmpty
            ? 'Puanlar 1-2 yıldız; metin yazılmamış.'
            : 'Örnek: “$quote”',
        todo:
            'Yorumlara yanıt ver. Aynı şikâyet tekrar ediyorsa sonraki sürümde '
            'önce onu düzelt.',
      ),
    );
  }
  final ratings = [?s.appStoreRating, ?s.playRating]
      .where((r) => r.average != null)
      .toList();
  final count = ratings.fold(0, (a, r) => a + r.count);
  if (count > 0) {
    final avg =
        ratings.fold<double>(0, (a, r) => a + r.average! * r.count) / count;
    final stars = avg.toStringAsFixed(1).replaceFirst('.', ',');
    if (count >= 5 && avg < 3.5) {
      out.add(
        Insight(
          InsightKind.problem,
          'Son 30 günün puanı $stars',
          why:
              'Ortalama 3,5\'in altında; mağazada dönüşümü ve sıralamayı '
              'aşağı çeker.',
          todo:
              'Kötü yorumlardaki ortak şikâyeti bul ve düzelt. Mutlu anlarda '
              'uygulama içinden puan iste.',
        ),
      );
    } else if (count >= 10 && avg >= 4.5) {
      out.add(
        Insight(
          InsightKind.good,
          'Yorumlar çok iyi: $stars yıldız',
          why: 'Son 30 günde $count yorumun ortalaması.',
          todo:
              'Puan istemenin tam zamanı: memnun kullanıcılara uygulama içi '
              'değerlendirme penceresini göster.',
        ),
      );
    }
  }

  // Raporu gecikmiş mağaza.
  for (final (name, data) in stores) {
    final last = data.last;
    if (last == null) continue;
    final age = DateTime.now().difference(DateTime.parse(last.date)).inDays;
    if (age > 4) {
      out.add(
        Insight(
          InsightKind.problem,
          '$name raporu $age gündür gelmiyor',
          why: 'Son rapor ${last.short} tarihli; normalde 1-2 gün gecikir.',
          todo: name == 'App Store'
              ? 'Anahtarın rolünü (Admin, Finance ya da Sales) ve satıcı '
                    'numarasını Ayarlar\'da kontrol et.'
              : 'Servis hesabının toplu rapor iznini Play Console\'da kontrol '
                    'et.',
        ),
      );
    }
  }

  out.sort((a, b) => a.kind.index.compareTo(b.kind.index));
  return out.take(max).toList();
}
