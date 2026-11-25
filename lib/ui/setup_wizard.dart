import 'package:flutter/material.dart';

import '../data/app_state.dart';
import 'ga4_settings.dart';
import 'logos.dart';
import 'store_settings.dart';
import 'theme.dart';

/// Adım adım kurulum: her veri kaynağı için ne verdiği, ne hazırlanması
/// gerektiği ve bağlama düğmesi. Tüm adımlar atlanabilir.
Future<void> showSetupWizard(BuildContext context, AppState state) {
  return showDialog(
    context: context,
    builder: (_) => Dialog(
      backgroundColor: AppColors.card,
      insetPadding: const EdgeInsets.all(14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.cardBorder),
      ),
      child: _Wizard(state: state),
    ),
  );
}

class _Step {
  const _Step({
    required this.source,
    required this.title,
    required this.gives,
    required this.needs,
    required this.connected,
    required this.error,
    required this.open,
  });

  final String source;
  final String title;
  final String gives;
  final List<String> needs;
  final bool Function(AppState) connected;
  final String? Function(AppState) error;
  final Future<void> Function(BuildContext, AppState) open;
}

final _steps = [
  _Step(
    source: 'GA4',
    title: 'Google Analytics 4',
    gives: 'Anlık ve günlük aktif kullanıcı, oturum süresi, D1/D7 tutma.',
    needs: const [
      'Google hesabıyla giriş ya da servis hesabı JSON anahtarı.',
      'Servis hesabı kullanıyorsanız GA4 > Yönetici > Mülk erişimi\'nde '
          'e-postasına "Görüntüleyen" rolü verin.',
    ],
    connected: (s) => s.ga4 != null,
    error: (s) => s.ga4Error,
    open: showGa4Settings,
  ),
  _Step(
    source: 'App Store',
    title: 'App Store Connect',
    gives: 'Günlük indirme, net gelir (proceeds), puan ve kötü yorumlar.',
    needs: const [
      'Users and Access > Integrations > App Store Connect API\'de '
          'Finance rolüyle anahtar oluşturun, .p8 dosyasını indirin '
          '(yalnız bir kez indirilebilir).',
      'Aynı sayfadan Key ID ve Issuer ID.',
      'Payments and Financial Reports sayfasının sol üstündeki vendor '
          'numarası.',
    ],
    connected: (s) => s.appStore != null,
    error: (s) => s.appStoreError,
    open: showAppStoreSettings,
  ),
  _Step(
    source: 'Google Play',
    title: 'Google Play',
    gives: 'Günlük kurulum, tahmini net gelir, aktif abone, puan ve yorumlar.',
    needs: const [
      'Play Console > Raporları indir > İstatistikler\'deki Cloud Storage '
          'URI (gs://pubsite_prod_…, "Cloud Storage URI\'sini kopyala").',
      'Play Console\'a erişimi olan Google hesabıyla giriş. Gelir için '
          'hesabın "Finansal verileri görüntüleme" izni olmalı.',
      'İsterseniz giriş yerine servis hesabı JSON\'u da kullanılabilir.',
    ],
    connected: (s) => s.play != null,
    error: (s) => s.playError,
    open: showPlaySettings,
  ),
  _Step(
    source: 'AdMob',
    title: 'AdMob',
    gives: 'Bugünkü ve bu ayki reklam geliri, eCPM.',
    needs: const ['AdMob hesabının bağlı olduğu Google hesabıyla giriş.'],
    connected: (s) => s.admob != null,
    error: (s) => s.admobError,
    open: showAdmobSettings,
  ),
];

class _Wizard extends StatefulWidget {
  const _Wizard({required this.state});

  final AppState state;

  @override
  State<_Wizard> createState() => _WizardState();
}

class _WizardState extends State<_Wizard> {
  /// 0 giriş, 1..n kaynaklar, n+1 bitiş.
  int _page = 0;

  int get _last => _steps.length + 1;

  Future<void> _finish() async {
    await widget.state.markSetupDone();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: ListenableBuilder(
        listenable: widget.state,
        builder: (context, _) => Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    'Kurulum',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  for (var i = 0; i <= _last; i++)
                    Container(
                      width: 7,
                      height: 7,
                      margin: const EdgeInsets.only(left: 5),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i == _page
                            ? AppColors.play
                            : AppColors.muted.withValues(alpha: 0.35),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              if (_page == 0)
                const _Intro()
              else if (_page == _last)
                _Done(state: widget.state)
              else
                _StepView(step: _steps[_page - 1], state: widget.state),
              const SizedBox(height: 16),
              Row(
                children: [
                  if (_page > 0)
                    TextButton(
                      onPressed: () => setState(() => _page--),
                      child: const Text('Geri'),
                    ),
                  const Spacer(),
                  if (_page == 0)
                    TextButton(
                      onPressed: _finish,
                      child: const Text('Şimdi değil'),
                    ),
                  const SizedBox(width: 6),
                  FilledButton(
                    onPressed: _page == _last
                        ? _finish
                        : () => setState(() => _page++),
                    child: Text(switch (_page) {
                      0 => 'Başla',
                      _ when _page == _last => 'Bitir',
                      _ when _steps[_page - 1].connected(widget.state) =>
                        'İleri',
                      _ => 'Atla',
                    }),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'App Signal dört kaynaktan veri okur: GA4, App Store Connect, Google '
      'Play ve AdMob. Her adımda o kaynağın ne verdiğini ve neyi hazırlamanız '
      'gerektiğini göreceksiniz. Kullanmadığınız kaynağı atlayın; sonra '
      'Ayarlar\'dan ekleyebilirsiniz.\n\nAnahtarlar yalnız bu bilgisayarın '
      'şifre kasasında saklanır.',
      style: TextStyle(fontSize: 13, height: 1.45),
    );
  }
}

class _StepView extends StatelessWidget {
  const _StepView({required this.step, required this.state});

  final _Step step;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final connected = step.connected(state);
    final error = step.error(state);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            ?sourceLogo(step.source, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                step.title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (connected)
              const Row(
                children: [
                  Icon(Icons.check_circle, size: 16, color: AppColors.play),
                  SizedBox(width: 4),
                  Text(
                    'Bağlı',
                    style: TextStyle(fontSize: 12, color: AppColors.play),
                  ),
                ],
              ),
          ],
        ),
        const SizedBox(height: 10),
        _Label('NE VERİR'),
        Text(step.gives, style: const TextStyle(fontSize: 13, height: 1.4)),
        const SizedBox(height: 10),
        _Label('HAZIRLAYIN'),
        for (final (i, n) in step.needs.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 18,
                  child: Text(
                    '${i + 1}.',
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.muted,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    n,
                    style: const TextStyle(fontSize: 12.5, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        if (error != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0x22FF6B6B),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              error,
              style: const TextStyle(
                fontSize: 12.5,
                color: Color(0xFFFF8A8A),
                height: 1.4,
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => step.open(context, state),
          icon: Icon(connected ? Icons.tune : Icons.link, size: 16),
          label: Text(connected ? 'Ayarları aç' : 'Bağla'),
        ),
      ],
    );
  }
}

class _Done extends StatelessWidget {
  const _Done({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final on = [
      for (final s in _steps)
        if (s.connected(state)) s.title,
    ];
    return Text(
      on.isEmpty
          ? 'Hiçbir kaynak bağlanmadı. İstediğiniz zaman sağ üstteki Ayarlar '
                'düğmesinden bağlayabilirsiniz.'
          : 'Bağlı: ${on.join(', ')}.\n\nVeriler birkaç saniyede gelir. '
                'Mağazalar raporu bir iki gün gecikmeli verir; ilk günlerde '
                'kartlar boş görünebilir.',
      style: const TextStyle(fontSize: 13, height: 1.45),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 10.5,
          letterSpacing: 0.8,
          fontWeight: FontWeight.w700,
          color: AppColors.muted,
        ),
      ),
    );
  }
}
