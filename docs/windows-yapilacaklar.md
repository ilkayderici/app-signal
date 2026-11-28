# Windows'ta yapılacaklar

Uygulama şu an yalnız macOS'ta derlenip dağıtılıyor (`dist/` içinde yalnız Mac zip'leri ve `appcast.xml` var). Windows tarafında kod var ama derlenip denenmedi. Bu liste bir Windows makinesinde yapılacak işleri toplar.

## 1. İlk derleme ve deneme

- Visual Studio 2022 ("Desktop development with C++") ve Flutter kur.
- `flutter pub get`, ardından `flutter run -d windows`.
- `assets/admob_oauth_client.json` repoda yok (`.gitignore`). Mac'ten güvenli yoldan kopyala; yoksa Google ile giriş çalışmaz.
- Her kaynağı tek tek bağla: GA4, AdMob, App Store Connect (`.p8`), Google Play. Her kartı ekranda kendin denetle.

## 2. Pencere konumu ve davranışı

- `lib/ui/edge_dock.dart`: `_supported` yalnız `Platform.isMacOS`. Windows'ta pencere yalnız `windowManager.show()` ile açılıyor, sağ üste yerleşmiyor.
  - Yapılacak: Windows'ta da ekranın çalışma alanını (görev çubuğu hariç) alıp pencereyi sağ üste koy. `screen_retriever` paketi ya da `windows/runner` içinde `app_signal/screen` kanalı (`SystemParametersInfo(SPI_GETWORKAREA)`, `GetCursorPos`) olabilir.
  - Kenar hareketiyle açılma istenirse aynı kanal `cursor` ve `visibleFrame` yöntemlerini Windows'ta da vermeli. README şu an "Windows'ta tepsi simgesinden açılır" diyor; kenar eklenirse README'yi güncelle.
- `windows/runner/main.cpp`: ilk pencere 1280x720 ve `(10, 10)` konumunda oluşuyor; `window_manager` sonra 420x720 yapıyor. Açılışta kısa bir sıçrama görünebilir. Boyutu baştan 420x720 yap.
- Cam (bulanık arka plan) ve yuvarlak köşe yalnız Mac'te (`macos/Runner/MainFlutterWindow.swift`, `GlassViewController`). Windows'ta pencere düz görünür. İstenirse Mica/Acrylic (`flutter_acrylic` ya da `DwmSetWindowAttribute`) ve Windows 11 yuvarlak köşe eklenebilir.
- `skipTaskbar: true` ve `alwaysOnTop: true` Windows'ta denenmeli: görev çubuğunda görünmemeli, öbür pencerelerin önünde kalmalı.
- Tek örnek yok: uygulama iki kez açılırsa iki tepsi simgesi olur. `main.cpp` içinde adlı mutex ile ikinci örneği engelle, ilk pencereyi öne getir.

## 3. Sistem tepsisi

- `assets/tray_icon.ico` var; açık ve koyu görev çubuğunda okunur mu bak. `isTemplate` Windows'ta etkisiz.
- Menü çubuğundaki canlı kullanıcı sayısı ve ⚠ yalnız Mac'te (`lib/main.dart`, `_updateTitle`, `trayManager.setTitle`). Windows tepsisi başlık göstermez. Yapılacak: aynı bilgiyi `trayManager.setToolTip` ile ipucuna yaz (ör. `App Signal · 12 canlı ⚠`).
- Sol tık pencereyi açıp kapatmalı, sağ tık menüyü açmalı. Windows'ta ikisini de dene.

## 4. Bildirimler

- `lib/data/drops.dart`, `Notifier.show`: `InitializationSettings` ve `NotificationDetails` yalnız `macOS` ayarı veriyor. Windows'ta düşüş ve kötü yorum bildirimi çıkmaz.
- Yapılacak: `flutter_local_notifications` Windows ayarlarını ekle (`WindowsInitializationSettings`: `appName`, `appUserModelId`, `guid`). Bildirim için uygulama kimliği (AUMID) gerekir; kurulum programı Başlat menüsü kısayolunu bu kimlikle oluşturmalı.

## 5. Anahtar saklama

- `lib/data/secret_store.dart` yalnız `MacOsOptions` veriyor; Windows varsayılanı kullanılıyor.
- Denetle: servis hesabı JSON'u ve `.p8` kaydedilip uygulama yeniden açıldığında okunuyor mu. Kimlik Bilgisi Yöneticisi kayıt boyutunu sınırlar; büyük JSON'larda yazma hatası olursa `WindowsOptions` ayarlarına bak.
- `adopt()` Mac imza geçişi için; Windows'ta zararsız ama gereksiz. İstenirse `Platform.isMacOS` ile sınırla.

## 6. Google ile giriş

- `obtainAccessCredentialsViaUserConsent` yerel bir HTTP sunucusu açıp tarayıcıdan dönüşü bekler. Windows Güvenlik Duvarı ilk seferde izin sorabilir. Girişi uçtan uca dene (AdMob, GA4, Play).

## 7. Arka planda sayım

- Mac'te App Nap kapatıldı (commit `5f01ab3`), pencere gizliyken 5 dakikalık yenileme sürüyor. Windows'ta karşılığı verimlilik modu (EcoQoS) olabilir.
- Denetle: pencere gizliyken 30 dakikadan uzun bekle, sonra kurulum (first_open) dakikalarında boşluk var mı bak. Boşluk varsa `SetProcessInformation(ProcessPowerThrottling)` ile kısıtlamayı kapat.

## 8. Paketleme ve otomatik güncelleme

- `windows/runner/Runner.rc`: `EdDSAPub` açık anahtarı var. `ProductName`, `FileDescription`, `InternalName` hâlâ `app_signal`; `App Signal` yap. `CompanyName` `dev.appsignal`.
- Kurulum programı yok. Inno Setup (ya da MSIX) betiği yaz: Program Files'a kur, Başlat menüsü kısayolu (AUMID ile), isteğe bağlı oturum açılışında başlatma.
- `auto_updater` Windows'ta WinSparkle kullanır. Kurulum `.exe`'sini Sparkle özel anahtarıyla imzala (anahtar Mac anahtar zincirinde; `docs/surum-cikarma.md`, İmza anahtarı bölümü). İmzalama Mac'te `sign_update` ile yapılabilir.
- `appcast-windows.xml` yaz ve her sürümde GitHub sürümüne ekle. `lib/data/updater.dart` Windows'ta bu adrese bakıyor; dosya yoksa denetim hata verir.
- Kod imzası (Authenticode) yok. İmzasız `.exe` SmartScreen uyarısı verir. Dağıtım için sertifika düşün.

## 9. Belgeler

- README'de derleme bölümüne `flutter run -d windows` ve kurulum adımlarını ekle.
- `docs/surum-cikarma.md` 6. adımı (Windows) gerçek komutlarla doldur.
