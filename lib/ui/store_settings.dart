import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../data/app_state.dart';
import '../data/appstore_client.dart';
import 'theme.dart';

Future<void> _show(BuildContext context, Widget child) {
  return showDialog(
    context: context,
    builder: (_) => Dialog(
      backgroundColor: AppColors.card,
      insetPadding: const EdgeInsets.all(14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.cardBorder),
      ),
      child: child,
    ),
  );
}

/// App Store Connect bağlama: .p8 anahtar, Key ID, Issuer ID, Vendor.
Future<void> showAppStoreSettings(BuildContext context, AppState state) =>
    _show(context, _AppStoreSettings(state: state));

/// AdMob bağlama: gömülü OAuth istemcisiyle Google girişi.
Future<void> showAdmobSettings(BuildContext context, AppState state) =>
    _show(context, _AdmobSettings(state: state));

/// Google Play bağlama: rapor kovası, Google girişi ya da servis hesabı.
Future<void> showPlaySettings(BuildContext context, AppState state) =>
    _show(context, _PlaySettings(state: state));

class _AppStoreSettings extends StatefulWidget {
  const _AppStoreSettings({required this.state});

  final AppState state;

  @override
  State<_AppStoreSettings> createState() => _AppStoreSettingsState();
}

class _AppStoreSettingsState extends State<_AppStoreSettings> {
  AppState get _app => widget.state;

  late final _keyId = TextEditingController(text: _app.pref('appstore.keyId'));
  late final _issuer = TextEditingController(
    text: _app.pref('appstore.issuer'),
  );
  late final _vendor = TextEditingController(
    text: _app.pref('appstore.vendor'),
  );
  String? _p8;
  String? _fileName;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _keyId.dispose();
    _issuer.dispose();
    _vendor.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'p8', extensions: ['p8']),
      ],
    );
    if (file == null) return;
    final text = await file.readAsString();
    setState(() {
      _p8 = text;
      _fileName = file.name;
      final id = AppStoreClient.keyIdFromFileName(file.name);
      if (id != null) _keyId.text = id;
    });
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _app.connectAppStore(
        p8: _p8,
        keyId: _keyId.text,
        issuerId: _issuer.text,
        vendor: _vendor.text,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final connected = _app.appStore != null;
    return _Frame(
      title: 'App Store Connect',
      busy: _busy,
      error: _error,
      help:
          'Users and Access > Integrations > App Store Connect API. '
          'Rolü Admin, Finance ya da Sales olan bir anahtar. Vendor numarası '
          'Payments and Financial Reports sayfasının üstünde.',
      fields: [
        _FileRow(
          label:
              _fileName ??
              (connected
                  ? 'Kayıtlı anahtar kullanılıyor'
                  : '.p8 dosyası seçin'),
          onPick: _busy ? null : _pick,
        ),
        _Field('Key ID', _keyId),
        _Field('Issuer ID', _issuer),
        _Field('Vendor numarası', _vendor),
      ],
      onSave: _busy || (_p8 == null && !connected) ? null : _save,
      onDisconnect: connected && !_busy
          ? () async {
              Navigator.of(context).pop();
              await _app.disconnectAppStore();
            }
          : null,
    );
  }
}

class _PlaySettings extends StatefulWidget {
  const _PlaySettings({required this.state});

  final AppState state;

  @override
  State<_PlaySettings> createState() => _PlaySettingsState();
}

class _PlaySettingsState extends State<_PlaySettings> {
  AppState get _app => widget.state;

  late final _bucket = TextEditingController(text: _app.pref('play.bucket'));
  String? _json;
  String? _label;
  bool _busy = false;
  bool _google = false;
  String? _error;

  @override
  void dispose() {
    _bucket.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'JSON', extensions: ['json']),
      ],
    );
    if (file == null) return;
    final text = await file.readAsString();
    setState(() {
      _json = text;
      _label = file.name;
    });
  }

  Future<void> _useGa4() async {
    final json = await _app.ga4Json();
    if (json == null) return;
    setState(() {
      _json = json;
      _label = 'GA4 anahtarı (${_app.ga4?.email ?? ''})';
    });
  }

  Future<void> _save({bool google = false}) async {
    setState(() {
      _busy = true;
      _google = google;
      _error = null;
    });
    try {
      if (google) {
        await _app
            .connectPlayWithGoogle(bucket: _bucket.text)
            .timeout(const Duration(minutes: 5));
      } else {
        await _app.connectPlay(json: _json, bucket: _bucket.text);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final connected = _app.play != null;
    final viaGoogle = connected && _app.play!.email == null;
    return _Frame(
      title: 'Google Play',
      busy: _busy,
      error: _error,
      help:
          'Cloud Storage URI: Play Console > Raporları indir > İstatistikler '
          '> "Cloud Storage URI\'sini kopyala" ile alıp olduğu gibi yapıştırın '
          '(gs://pubsite_prod_... ile başlar; tarayıcı adres çubuğundaki '
          'play.google.com bağlantısı değil). '
          'Sonra Play Console\'a erişimi olan hesapla Google ile giriş yapın. '
          'Gelir için hesabın "Finansal verileri görüntüleme" izni olmalı.',
      fields: [
        _Field('Cloud Storage URI (gs://pubsite_prod_...)', _bucket),
        if (_busy && _google)
          const Text(
            'Tarayıcıda Google girişini tamamlayın…',
            style: TextStyle(fontSize: 12, color: AppColors.muted),
          )
        else
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _save(google: true),
            icon: const Icon(Icons.login, size: 16),
            label: Text(
              viaGoogle
                  ? 'Google ile bağlı · yeniden giriş'
                  : 'Google ile giriş',
            ),
          ),
        const Text(
          'ya da servis hesabı JSON\'u (hesaba Play Console\'da "Uygulama '
          'bilgilerini görüntüleme ve toplu raporları indirme" izni verin):',
          style: TextStyle(fontSize: 11, color: AppColors.muted, height: 1.4),
        ),
        _FileRow(
          label:
              _label ??
              (connected && !viaGoogle
                  ? 'Kayıtlı anahtar (${_app.play!.email})'
                  : 'Servis hesabı JSON dosyası seçin'),
          onPick: _busy ? null : _pick,
        ),
        if (_app.ga4 != null && _json == null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _busy ? null : _useGa4,
              child: const Text('GA4 anahtarını kullan'),
            ),
          ),
      ],
      onSave: _busy || (_json == null && !connected) ? null : _save,
      onDisconnect: connected && !_busy
          ? () async {
              Navigator.of(context).pop();
              await _app.disconnectPlay();
            }
          : null,
    );
  }
}

class _AdmobSettings extends StatefulWidget {
  const _AdmobSettings({required this.state});

  final AppState state;

  @override
  State<_AdmobSettings> createState() => _AdmobSettingsState();
}

class _AdmobSettingsState extends State<_AdmobSettings> {
  AppState get _app => widget.state;

  bool _busy = false;
  String? _error;

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _app.connectAdmob().timeout(const Duration(minutes: 5));
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final connected = _app.admob != null;
    return _Frame(
      title: 'AdMob',
      busy: _busy,
      error: _error,
      help:
          'Google ile giriş yapın. AdMob hesabının sahibi ya da hesaba ekli '
          'bir kullanıcı olmalı. Yalnız okuma izni istenir.',
      fields: [
        Text(
          _busy
              ? 'Tarayıcıda Google girişini tamamlayın…'
              : connected
              ? 'Bağlı (${_app.admob!.publisher.split('/').last})'
              : 'Bağlı değil',
          style: const TextStyle(fontSize: 12, color: AppColors.muted),
        ),
      ],
      saveLabel: connected ? 'Yeniden giriş' : 'Google ile giriş',
      onSave: _busy ? null : _save,
      onDisconnect: connected && !_busy
          ? () async {
              Navigator.of(context).pop();
              await _app.disconnectAdmob();
            }
          : null,
    );
  }
}

class _Frame extends StatelessWidget {
  const _Frame({
    required this.title,
    required this.busy,
    required this.error,
    required this.help,
    required this.fields,
    required this.onSave,
    required this.onDisconnect,
    this.saveLabel = 'Kaydet',
  });

  final String title;
  final bool busy;
  final String? error;
  final String help;
  final List<Widget> fields;
  final VoidCallback? onSave;
  final VoidCallback? onDisconnect;
  final String saveLabel;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 380,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              help,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.muted,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 14),
            for (final f in fields) ...[f, const SizedBox(height: 10)],
            if (busy) const LinearProgressIndicator(minHeight: 1.5),
            if (error != null)
              Text(
                error!,
                style: const TextStyle(color: Color(0xFFFF9B9B), fontSize: 12),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (onDisconnect != null)
                  TextButton(
                    onPressed: onDisconnect,
                    child: const Text('Bağlantıyı kaldır'),
                  ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Kapat'),
                ),
                const SizedBox(width: 6),
                FilledButton(onPressed: onSave, child: Text(saveLabel)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({required this.label, required this.onPick});

  final String label;
  final VoidCallback? onPick;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12),
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton(onPressed: onPick, child: const Text('Dosya seç')),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  const _Field(this.label, this.controller);

  final String label;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
    );
  }
}
