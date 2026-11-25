import 'package:flutter/material.dart';

import '../data/app_state.dart';
import 'ga4_settings.dart';
import 'logos.dart';
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
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Kapat'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
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
