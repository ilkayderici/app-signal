# Windows'ta yapılacaklar

Windows kodu yazıldı ama henüz derlenip denenmedi. Bu makinedeki Visual Studio 2022'de "Desktop development with C++" iş yükü eksik (MSVC, C++ CMake araçları, Windows 10/11 SDK). Bu liste kalan işleri toplar.

## Şimdi: 1.0.5 Windows kurulumunu çıkar

Mac 1.0.5 yayında (GitHub sürümü `v1.0.5`). Sürümde Windows dosyaları yok; Windows'taki uygulama güncelleme bulamaz. Sırayla:

### Windows'ta

1. `git pull`. `pubspec.yaml` `version: 1.0.5+6` olmalı; değiştirme.
2. Visual Studio "Desktop development with C++" iş yükü ve Inno Setup 6 kurulu olsun. `flutter doctor` temiz çıkmalı.
3. `assets/admob_oauth_client.json` yerinde olsun (Mac'ten güvenli yoldan kopyala). Yoksa Google ile giriş çalışmaz.
4. Önce dene: `flutter run -d windows`. Derleme hatası çıkarsa düzelt, commit'le, pushla. Aşağıdaki "Derleme ve elle deneme" maddelerine bak.
5. Derle: `flutter build windows --release`.
6. Paketle: `& "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" /DAppVersion=1.0.5 windows\installer\app_signal.iss`. Çıktı: `dist\AppSignal-1.0.5-setup.exe`.
7. Kurulumu bir kez elle çalıştır: uygulama açılmalı, Başlat menüsünde görünmeli.
8. `.exe`'yi sürüme yükle: `gh release upload v1.0.5 dist\AppSignal-1.0.5-setup.exe`.
9. `appcast-windows.xml` yükleme. İmza Mac'te atılır.

### Mac'te (exe yüklendikten sonra)

1. İndir: `gh release download v1.0.5 -p "AppSignal-1.0.5-setup.exe" -D dist/v1.0.5`.
2. İmzala: `macos/Pods/Sparkle/bin/sign_update dist/v1.0.5/AppSignal-1.0.5-setup.exe`. `sparkle:edSignature` ve `length` değerlerini al.
3. `windows/installer/appcast-windows.template.xml`'i `dist/v1.0.5/appcast-windows.xml` olarak doldur: SURUM `1.0.5`, BUILD `6`, tarih, imza, boyut.
4. Yükle: `gh release upload v1.0.5 dist/v1.0.5/appcast-windows.xml`.
5. Denetle: `https://github.com/ilkayderici/app-signal/releases/latest/download/appcast-windows.xml` açılmalı.

Bundan sonra Windows'taki uygulama Ayarlar > "Güncellemeleri denetle" ile 1.0.5'i görür. Sonraki sürümlerde aynı akış: önce Windows exe'yi yükler, sonra Mac imzalar.

## Yapıldı

- `windows/runner/main.cpp`: pencere baştan 420x720 açılıyor, başlık `App Signal`. Adlı mutex ile tek örnek var: ikinci açılış ilk pencereyi öne getirip çıkıyor. Güç kısıtlaması (EcoQoS) `SetProcessInformation(ProcessPowerThrottling)` ile kapalı.
- `windows/runner/flutter_window.cpp`: `app_signal/screen` kanalı `cursor` ve `visibleFrame` yöntemlerini veriyor. Değerler mantıksal piksel; ana ekranın çalışma alanı (görev çubuğu hariç) kullanılıyor.
- `lib/ui/edge_dock.dart`: kenar hareketi ve sağ üste yerleşme Windows'ta da açık.
- `lib/main.dart`: canlı kullanıcı sayısı ve ⚠ Windows'ta tepsi ipucunda (`App Signal · 12 canlı · ⚠`).
- `lib/data/drops.dart`: Windows bildirim ayarları (`appUserModelId` `dev.appsignal.AppSignal`).
- `lib/data/secret_store.dart`: `adopt()` yalnız macOS'ta çalışıyor. Windows eklentisi veriyi DPAPI ile şifreli dosyada tutuyor; Kimlik Bilgisi Yöneticisi boyut sınırı yok.
- `windows/runner/Runner.rc`: ürün adları `App Signal`.
- `windows/installer/app_signal.iss`: Inno Setup 6 betiği (kullanıcı başına kurulum, `%LOCALAPPDATA%\Programs`, UAC yok; AUMID'li Başlat menüsü kısayolu, isteğe bağlı oturum açılışında başlatma, sessiz güncellemede uygulamayı kapatıp yeniden açma).
- `windows/installer/appcast-windows.template.xml`: WinSparkle appcast şablonu.
- README ve `docs/surum-cikarma.md` 6. adım güncellendi.

## Kalan

### Kurulum

- Visual Studio Installer'da "Desktop development with C++" iş yükünü kur. `flutter doctor` temiz olmalı.
- [Inno Setup 6](https://jrsoftware.org/isinfo.php) kur.
- `assets/admob_oauth_client.json` repoda yok (`.gitignore`). Mac'ten güvenli yoldan kopyala; yoksa Google ile giriş çalışmaz.

### Derleme ve elle deneme

- `flutter run -d windows`, sonra `flutter build windows --release`. C++ kodu ilk kez burada derlenecek; hata çıkarsa düzelt.
- Her kaynağı bağla: GA4, AdMob, App Store Connect (`.p8`), Google Play. Kartları ekranda denetle.
- Servis hesabı JSON'u ve `.p8` kaydedilip uygulama yeniden açılınca okunuyor mu bak.
- Pencere sağ üste, görev çubuğunun üstüne yerleşiyor mu; ölçek %125/%150'de konum doğru mu bak.
- İmleci ana ekranın sağ kenarına götür: pencere açılmalı.
- `skipTaskbar` ve `alwaysOnTop`: görev çubuğunda görünmemeli, öbür pencerelerin önünde kalmalı.
- Uygulamayı ikinci kez aç: yeni tepsi simgesi çıkmamalı, ilk pencere öne gelmeli.
- Tepsi: sol tık pencereyi açıp kapatmalı, sağ tık menüyü açmalı. `assets/tray_icon.ico` açık ve koyu görev çubuğunda okunur mu bak.
- Bildirim: kurulum programıyla kur (Başlat menüsü kısayolu AUMID'i taşır), sonra düşüş ve kötü yorum bildirimini dene. `flutter run` ile kurulumsuz çalışırken bildirim çıkmayabilir.
- Google ile giriş: yerel HTTP sunucusu açılır, Windows Güvenlik Duvarı izin sorabilir. AdMob, GA4 ve Play girişini uçtan uca dene.
- Arka plan: pencere gizliyken 30 dakikadan uzun bekle, first_open dakikalarında boşluk var mı bak.

### Paketleme

- İlk Windows sürümünü `docs/surum-cikarma.md` 6. adımla çıkar. `appcast-windows.xml` GitHub sürümünde yoksa güncelleme denetimi hata verir.
- Kod imzası (Authenticode) yok; imzasız `.exe` SmartScreen uyarısı verir. Dağıtım için sertifika düşün.

### İsteğe bağlı

- Cam (bulanık arka plan) ve yuvarlak köşe yalnız Mac'te. Windows'ta Mica/Acrylic (`flutter_acrylic` ya da `DwmSetWindowAttribute`) ve Windows 11 yuvarlak köşe eklenebilir.
- Kenar hareketi yalnız ana ekranda çalışıyor; çoklu ekranda imlecin olduğu ekranı kullanmak istenirse kanalı genişlet.
