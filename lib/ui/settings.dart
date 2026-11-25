import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../data/app_state.dart';
import '../data/updater.dart';
import 'ga4_settings.dart';
import 'logos.dart';
import 'setup_wizard.dart';
import 'store_settings.dart';
import 'theme.dart';

/// Tüm veri kaynaklarının tek ayar ekranı. Her satır kendi bağlama
/// penceresini açar.
Future<void> showSettings(BuildContext context, AppState state) {
  return showDialog(
    context: context,
    builder: (_) => Dialog(
      backgroundColor: AppColors.card,
      insetPadding: const EdgeInsets.all(14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.cardBorder),
      ),
      child: ListenableBuilder(
        listenable: state,
        builder: (context, _) => Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Ayarlar',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              const Text(
                'Veri kaynaklarını bağlayın. Anahtarlar yalnız bu bilgisayarın '
                'şifre kasasında saklanır.',
                style: TextStyle(fontSize: 12, color: AppColors.muted),
              ),
              const SizedBox(height: 14),
              _Row(
                source: 'GA4',
                title: 'Google Analytics 4',
                connected: state.ga4 != null,
                error: state.ga4Error,
                onTap: () => showGa4Settings(context, state),
              ),
              _Row(
                source: 'App Store',
                title: 'App Store Connect',
                connected: state.appStore != null,
                error: state.appStoreError,
                onTap: () => showAppStoreSettings(context, state),
              ),
              _Row(
                source: 'Google Play',
                title: 'Google Play',
                connected: state.play != null,
                error: state.playError,
                onTap: () => showPlaySettings(context, state),
              ),
              _Row(
                source: 'AdMob',
                title: 'AdMob',
                connected: state.admob != null,
                error: state.admobError,
                onTap: () => showAdmobSettings(context, state),
              ),
              const SizedBox(height: 6),
              const _VersionRow(),
              const SizedBox(height: 6),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () => showSetupWizard(context, state),
                    icon: const Icon(Icons.auto_fix_high, size: 16),
                    label: const Text('Kurulum sihirbazı'),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Kapat'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Kurulu sürüm ve elle güncelleme denetimi.
class _VersionRow extends StatelessWidget {
  const _VersionRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        FutureBuilder(
          future: PackageInfo.fromPlatform(),
          builder: (context, snap) => Text(
            snap.data == null
                ? 'Sürüm'
                : 'Sürüm ${snap.data!.version} (${snap.data!.buildNumber})',
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          ),
        ),
        const Spacer(),
        TextButton.icon(
          onPressed: () {
            if (kDebugMode) {
              ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                const SnackBar(
                  content: Text('Debug derlemede güncelleme denetimi kapalı.'),
                ),
              );
              return;
            }
            Updater.checkNow();
          },
          icon: const Icon(Icons.system_update_alt, size: 16),
          label: const Text('Güncellemeleri denetle'),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.source,
    required this.title,
    required this.connected,
    required this.onTap,
    this.error,
  });

  final String source;
  final String title;
  final bool connected;
  final String? error;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (status, statusColor) = error != null
        ? ('Hata', const Color(0xFFFF6B6B))
        : connected
        ? ('Bağlı', AppColors.play)
        : ('Bağlı değil', AppColors.muted);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                SizedBox(
                  width: 22,
                  child: Center(child: sourceLogo(source, size: 18)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  status,
                  style: TextStyle(fontSize: 12, color: statusColor),
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: AppColors.muted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
