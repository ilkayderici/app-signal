import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/app_state.dart';
import '../data/ga4_client.dart';
import 'theme.dart';

/// GA4 bağlama penceresi: JSON yükle, mülk seç, kırılım boyutunu seç.
Future<void> showGa4Settings(BuildContext context, AppState state) {
  return showDialog(
    context: context,
    builder: (_) => Dialog(
      backgroundColor: AppColors.card,
      insetPadding: const EdgeInsets.all(14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.cardBorder),
      ),
      child: _Ga4Settings(state: state),
    ),
  );
}

class _Ga4Settings extends StatefulWidget {
  const _Ga4Settings({required this.state});

  final AppState state;

  @override
  State<_Ga4Settings> createState() => _Ga4SettingsState();
}

class _Ga4SettingsState extends State<_Ga4Settings> {
  AppState get _app => widget.state;

  bool _busy = false;
  String? _error;
  List<Ga4Property>? _properties;
  Ga4Property? _property;
  Ga4Metadata? _meta;
  String? _gameDim;
  String? _durationMetric;
  String? _revenueMetric;
  int _limit = 5;

  @override
  void initState() {
    super.initState();
    if (_app.ga4 != null) _loadProperties();
  }

  Future<void> _run(Future<void> Function() job) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await job();
    } catch (e) {
      _error = '$e';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickJson() => _run(() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'JSON', extensions: ['json']),
      ],
    );
    if (file == null) return;
    await _app.connectGa4(await file.readAsString());
    await _loadPropertiesInner();
  });

  Future<void> _google() => _run(() async {
    await _app.connectGa4WithGoogle().timeout(const Duration(minutes: 5));
    await _loadPropertiesInner();
  });

  Future<void> _loadProperties() => _run(_loadPropertiesInner);

  Future<void> _loadPropertiesInner() async {
    final list = await _app.ga4!.properties();
    _properties = list;
    final saved = _app.ga4Settings;
    final pick =
        list.where((p) => p.id == saved?.propertyId).firstOrNull ??
        (list.length == 1 ? list.first : null);
    if (pick != null) await _selectInner(pick, keepSaved: saved != null);
  }

  Future<void> _select(Ga4Property p) => _run(() => _selectInner(p));

  Future<void> _selectInner(Ga4Property p, {bool keepSaved = false}) async {
    _property = p;
    _limit = _app.ga4Settings?.gameLimit ?? 5;
    final meta = await _app.ga4!.metadata(p.id);
    _meta = meta;
    final saved = keepSaved ? _app.ga4Settings : null;
    _gameDim =
        saved?.gameDimension ??
        Ga4Metadata.guess(meta.dimensions, ['game', 'oyun', 'level']);
    _durationMetric =
        saved?.durationMetric ??
        Ga4Metadata.guess(meta.metrics, ['duration', 'sure', 'time']);
    _revenueMetric =
        saved?.revenueMetric ??
        Ga4Metadata.guess(meta.metrics, ['revenue', 'gelir']);
  }

  Future<void> _save() async {
    final p = _property;
    if (p == null) return;
    Navigator.of(context).pop();
    await _app.saveGa4Settings(
      Ga4Settings(
        propertyId: p.id,
        propertyName: p.name,
        gameDimension: _gameDim,
        durationMetric: _durationMetric,
        revenueMetric: _revenueMetric,
        gameLimit: _limit,
      ),
    );
  }

  Future<void> _disconnect() async {
    Navigator.of(context).pop();
    await _app.disconnectGa4();
  }

  @override
  Widget build(BuildContext context) {
    final client = _app.ga4;
    return Padding(
      padding: const EdgeInsets.all(18),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.analytics_outlined, color: AppColors.ga4, size: 20),
                SizedBox(width: 8),
                Text(
                  'Google Analytics 4',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (client == null) ...[
              const _Help(
                'Google ile giriş yapın; GA4\'e erişimi olan hesabınız yeter. '
                'Yalnız okuma izni istenir.',
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _busy ? null : _google,
                icon: const Icon(Icons.login, size: 18),
                label: const Text('Google ile giriş'),
              ),
              if (_busy) ...[
                const SizedBox(height: 8),
                const _Help('Tarayıcıda Google girişini tamamlayın…'),
              ],
              const SizedBox(height: 16),
              const _Help(
                'Ya da giriş yapmadan: Google Cloud\'da bir servis hesabı açıp '
                'JSON anahtarını seçin. Anahtar yalnız bu bilgisayarın şifre '
                'kasasında saklanır.',
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _busy ? null : _pickJson,
                icon: const Icon(Icons.upload_file, size: 18),
                label: const Text('JSON dosyası seç'),
              ),
            ] else ...[
              if (client.email == null)
                const _Help('Google girişiyle bağlı.')
              else ...[
                _EmailRow(client.email!),
                const SizedBox(height: 6),
                const _Help(
                  'Bu adresi GA4 > Yönetici > Mülk erişim yönetimi\'ne '
                  '"Görüntüleyen" olarak ekleyin.',
                ),
              ],
              const SizedBox(height: 14),
              if (_properties != null && _properties!.isEmpty)
                const _Help(
                  'Bu hesabın görebildiği mülk yok. Erişim ekledikten sonra '
                  'yenileyin.',
                ),
              if (_properties != null && _properties!.isNotEmpty)
                _Dropdown<Ga4Property?>(
                  label: 'Mülk',
                  value: _property,
                  items: {
                    for (final p in _properties!)
                      p: '${p.name}  ·  ${p.account}',
                  },
                  onChanged: _busy ? null : (p) => _select(p!),
                ),
              if (_meta != null) ...[
                const SizedBox(height: 10),
                _Dropdown<String?>(
                  label: 'Kırılım boyutu (ekran, içerik, seviye…)',
                  value: _gameDim,
                  items: {
                    null: 'Yok',
                    for (final f in _meta!.dimensions) f.apiName: f.label,
                  },
                  onChanged: (v) => setState(() => _gameDim = v),
                ),
                const SizedBox(height: 4),
                const _Help(
                  'İsteğe bağlı. Rakamları bir boyuta göre ayırmak istemiyorsanız '
                  '"Yok" bırakın; kırılım tablosu gizlenir.',
                ),
                const SizedBox(height: 10),
                _Dropdown<String?>(
                  label: 'Süre ölçüsü (saniye)',
                  value: _durationMetric,
                  items: {
                    null: 'Yok',
                    for (final f in _meta!.metrics) f.apiName: f.label,
                  },
                  onChanged: (v) => setState(() => _durationMetric = v),
                ),
                const SizedBox(height: 10),
                _Dropdown<String?>(
                  label: 'Gelir ölçüsü',
                  value: _revenueMetric,
                  items: {
                    null: 'Yok',
                    for (final f in _meta!.metrics) f.apiName: f.label,
                  },
                  onChanged: (v) => setState(() => _revenueMetric = v),
                ),
                const SizedBox(height: 10),
                _Dropdown<int?>(
                  label: 'Gösterilecek satır sayısı',
                  value: _limit,
                  items: const {3: '3', 5: '5', 10: '10', 20: '20', 0: 'Hepsi'},
                  onChanged: (v) => setState(() => _limit = v ?? 5),
                ),
              ],
            ],
            if (_busy) ...[
              const SizedBox(height: 14),
              const LinearProgressIndicator(minHeight: 2),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Color(0xFFFF6B6B))),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                if (client != null)
                  TextButton(
                    onPressed: _busy ? null : _disconnect,
                    child: const Text(
                      'Bağlantıyı kaldır',
                      style: TextStyle(color: AppColors.muted),
                    ),
                  ),
                if (client != null && _properties != null)
                  IconButton(
                    tooltip: 'Mülkleri yenile',
                    onPressed: _busy ? null : _loadProperties,
                    icon: const Icon(Icons.refresh, size: 18),
                  ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Kapat'),
                ),
                if (client != null) ...[
                  const SizedBox(width: 6),
                  FilledButton(
                    onPressed: _busy || _property == null ? null : _save,
                    child: const Text('Kaydet'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Help extends StatelessWidget {
  const _Help(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(color: AppColors.muted, fontSize: 13, height: 1.4),
  );
}

class _EmailRow extends StatelessWidget {
  const _EmailRow(this.email);

  final String email;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: SelectableText(email, style: const TextStyle(fontSize: 13)),
          ),
          IconButton(
            tooltip: 'Kopyala',
            iconSize: 16,
            onPressed: () => Clipboard.setData(ClipboardData(text: email)),
            icon: const Icon(Icons.copy),
          ),
        ],
      ),
    );
  }
}

class _Dropdown<T> extends StatelessWidget {
  const _Dropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final T value;
  final Map<T, String> items;
  final ValueChanged<T?>? onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      initialValue: items.containsKey(value) ? value : null,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
      items: [
        for (final e in items.entries)
          DropdownMenuItem(
            value: e.key,
            child: Text(e.value, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: onChanged,
    );
  }
}
