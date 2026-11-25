# Sürüm çıkarma ve otomatik güncelleme

App Signal güncellemeleri Sparkle (macOS) ve WinSparkle (Windows) ile kendisi kurar.
Uygulama günde bir kez şu adrese bakar:

- macOS: `https://github.com/ilkayderici/app-signal/releases/latest/download/appcast.xml`
- Windows: `https://github.com/ilkayderici/app-signal/releases/latest/download/appcast-windows.xml`

Menüdeki "Güncellemeleri denetle" aynı denetimi elle yapar. Debug derlemede denetim kapalıdır.

## İmza anahtarı

- Özel EdDSA anahtarı bu Mac'in anahtar zincirinde ("Private key for signing Sparkle updates"). Repoya girmez.
- Açık anahtar `macos/Runner/Info.plist` (`SUPublicEDKey`) ve `windows/runner/Runner.rc` (`EdDSAPub`) içinde.
- Özel anahtarı yedekle: `macos/Pods/Sparkle/bin/generate_keys -x sparkle_private_key.txt`, dosyayı güvenli yere koy, sonra sil. Kaybolursa eski kurulumlar yeni sürümü kabul etmez.

## Adımlar

1. `pubspec.yaml` içinde `version`'ı artır (ör. `1.0.1+2`). Sparkle karşılaştırmayı build numarasıyla yapar.
2. Derle: `flutter build macos --release`.
3. Paketle: `ditto -c -k --keepParent build/macos/Build/Products/Release/app_signal.app dist/AppSignal-1.0.1.zip`.
4. Appcast üret: `macos/Pods/Sparkle/bin/generate_appcast --download-url-prefix https://github.com/ilkayderici/app-signal/releases/download/v1.0.1/ dist/`. Bu, `dist/appcast.xml`'i imzayla yazar.
5. GitHub sürümü: `gh release create v1.0.1 dist/AppSignal-1.0.1.zip dist/appcast.xml --title "1.0.1" --notes "..."`.
6. Windows: `flutter build windows --release`, kurulum dosyasını (ör. Inno Setup `.exe`) `sign_update` ile imzala, `appcast-windows.xml`'i yaz ve aynı sürüme ekle.

## İmza (Apple)

Uygulama şu an geliştirme sertifikasıyla imzalı. Herkese dağıtım için Apple Developer ID imzası ve notarization gerekir:

- `codesign --deep --options runtime --sign "Developer ID Application: ..."`
- `xcrun notarytool submit ... --wait`, ardından `xcrun stapler staple`.

Developer ID olmadan Sparkle güncellemeyi yine kurar, ama kullanıcı ilk kurulumda Gatekeeper uyarısını elle geçer.
