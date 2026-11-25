# ilkayderici.com.tr için App Signal sayfaları (brief)

Bu iş ilkayderici.com.tr projesinde yapılacak (`~/ilkayderici.com.tr`, Vite + React, çok sayfalı, prerender'lı).

## Neden

Google Cloud'da App Signal'in OAuth onay ekranını "Testing"ten "In production"a almak gerekiyor.
Bunun için Branding sayfasına iki link girilmeli:

- **Uygulama ana sayfası:** `https://ilkayderici.com.tr/app-signal.html`
- **Gizlilik politikası:** `https://ilkayderici.com.tr/app-signal-gizlilik.html`

Authorized domain olarak `ilkayderici.com.tr` eklenecek. Bu adresler değişirse App Signal oturumuna söyle.

## Google'ın beklediği

- Sayfalar herkese açık olmalı; giriş istememeli.
- Ana sayfa uygulamanın adını ("App Signal") ve ne yaptığını anlatmalı. Gizlilik politikasına link vermeli.
- Gizlilik sayfası aynı alan adında olmalı. Google verisiyle ne yapıldığını açıkça söylemeli. "Limited Use" cümlesi şart (aşağıda).
- Prerender önemli: Google'ın denetçisi JS çalıştırmadan da metni görebilmeli.

## Yapılacaklar

1. İki yeni sayfa: `app-signal.html` ve `app-signal-gizlilik.html`. Mevcut düzene uy:
   - `vite.config.ts` içindeki `rollupOptions.input`
   - `src/entry-server.tsx` içindeki `pages`
   - `scripts/prerender.mjs` içindeki `pages`
   - `urunler.html` gibi bir HTML kabuğu ve giriş dosyası (`src/products.tsx` benzeri)
   - `public/sitemap.xml`
2. TR/EN iki dil, sitenin dil düğmesiyle çalışsın. Prerender TR, bu yüzden Google en azından TR metni görür. İstersen gizlilik sayfasının altına EN metni de sabit koy; Google denetçisi için faydalı.
3. `src/data.ts` → `products` listesine App Signal ekle:
   - durum `soon`
   - ikon için grafik/çubuk benzeri yeni bir glyph (`src/components/Ui.tsx`)
   - "Ayrıntılar" bağlantısı `app-signal.html`
   - Not: `ProductRow`'daki `link` yeni sekmede açılıyor (`ext`). Site içi link için bunu ayır.
4. Footer'a App Signal gizlilik linki eklemek iyi olur.
5. `npm run build` ile derle; `dist/app-signal*.html` içinde metnin prerender edildiğini kontrol et.
6. Push → GitHub Actions FTPS ile yayınlar. Yayından sonra iki adresin 200 döndüğünü kontrol et.

## Ana sayfa içeriği

**App Signal** · macOS ve Windows masaüstü uygulaması · durum: Yakında

Uygulama geliştiricileri için küçük bir masaüstü penceresi. Google Analytics 4, App Store Connect, Google Play ve AdMob'daki kendi rakamlarınızı tek yerde gösterir.

- Aktif kullanıcı, indirme, yorum ve reklam geliri tek pencerede
- Veriler Google ve Apple'dan doğrudan sizin bilgisayarınıza gelir
- Google erişimi yalnız okuma iznidir; hiçbir şey değiştirilmez
- Anahtarlar yalnız bilgisayarınızın şifre kasasında saklanır

Nasıl çalışır:

- **Bağlanın:** Google ile giriş yapın ya da servis hesabı / API anahtarı dosyanızı seçin.
- **İzleyin:** Pencere masaüstünüzde açık kalır, rakamlar kendiliğinden yenilenir.
- **Kontrol sizde:** Bir kaynağı istediğiniz an Ayarlar'dan ayırabilirsiniz.

Link: Gizlilik politikası → `app-signal-gizlilik.html`

EN: "A small desktop window for app developers. It shows your own numbers from Google Analytics 4, App Store Connect, Google Play and AdMob in one place." (Maddeler aynı anlamda çevrilir.)

## Gizlilik politikası metni

İçerik değişmesin. Özellikle izinler ve Limited Use cümlesi aynen kalsın.

### TR

**App Signal Gizlilik Politikası** · Son güncelleme: 25 Kasım 2026

App Signal, Google Analytics 4, App Store Connect, Google Play ve AdMob'daki kendi uygulama istatistiklerinizi küçük bir pencerede gösteren bir masaüstü uygulamasıdır. Bu politika, uygulamanın hangi verilere eriştiğini ve bunları nasıl işlediğini açıklar.

**Erişilen veriler**
- Google Analytics 4 (yalnız okuma, `analytics.readonly`): mülk listesi ve aktif kullanıcı, etkinlik gibi rapor rakamları.
- AdMob (yalnız okuma, `admob.readonly`): hesap adı, uygulama listesi ve tahmini kazanç.
- App Store Connect ve Google Play: sizin verdiğiniz anahtarlarla satış, indirme ve yorum verileri.

**Verilerin kullanımı**
Veriler yalnız size uygulama içinde istatistik göstermek için kullanılır. Google ve Apple sunucularından doğrudan bilgisayarınıza gelir. App Signal'in kendine ait bir sunucusu yoktur. Geliştirici verilerinizi almaz, toplamaz, saklamaz, satmaz ve kimseyle paylaşmaz.

**Saklama ve silme**
Giriş jetonları ve anahtar dosyaları yalnız bilgisayarınızda, işletim sisteminin şifre kasasında saklanır. Uygulamanın Ayarlar ekranından bir kaynağı ayırarak ya da uygulamayı silerek bunları istediğiniz an kaldırabilirsiniz. Google erişimini https://myaccount.google.com/permissions adresinden de geri alabilirsiniz.

**Google API Hizmetleri**
App Signal'in Google API'lerinden aldığı bilgileri kullanması ve aktarması, Sınırlı Kullanım (Limited Use) koşulları dahil [Google API Services User Data Policy](https://developers.google.com/terms/api-services-user-data-policy)'ye uygundur. Google kullanıcı verileri reklam için kullanılmaz, üçüncü taraflara aktarılmaz ve yapay zekâ modeli eğitmek için kullanılmaz.

**Çocuklar**
App Signal uygulama geliştiricilerine yönelik bir araçtır; çocuklara yönelik değildir.

**Değişiklikler**
Bu politika değişirse yeni sürüm bu sayfada yayınlanır.

**İletişim**
İlkay Derici · ilkayderici@gmail.com

### EN

**App Signal Privacy Policy** · Last updated: 25 November 2026

App Signal is a desktop app that shows your own app statistics from Google Analytics 4, App Store Connect, Google Play and AdMob in one small window. This policy explains what data the app accesses and how it is handled.

**Data the app accesses**
- Google Analytics 4 (read-only, `analytics.readonly`): property list and report numbers such as active users and events.
- AdMob (read-only, `admob.readonly`): account name, app list and estimated earnings.
- App Store Connect and Google Play: sales, download and review data, using keys you provide.

**How the data is used**
Data is used only to show statistics to you inside the app. It is fetched directly from Google and Apple servers to your computer. App Signal has no server of its own. The developer does not receive, collect, store, sell or share any of your data.

**Storage and deletion**
Sign-in tokens and key files are stored only on your computer, in the operating system's keychain. You can remove them at any time by disconnecting a source in the app's Settings, or by deleting the app. You can also revoke Google access at https://myaccount.google.com/permissions.

**Google API Services**
App Signal's use and transfer of information received from Google APIs adheres to the [Google API Services User Data Policy](https://developers.google.com/terms/api-services-user-data-policy), including the Limited Use requirements. Google user data is not used for advertising, not transferred to third parties, and not used to train AI models.

**Children**
App Signal is a tool for app developers and is not directed at children.

**Changes**
If this policy changes, the new version will be posted on this page.

**Contact**
İlkay Derici · ilkayderici@gmail.com
