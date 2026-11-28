import 'dart:io';

import 'package:flutter/material.dart';
import 'package:tray_manager/legacy.dart';
import 'package:window_manager/legacy.dart';

import 'data/app_state.dart';
import 'data/updater.dart';
import 'ui/dashboard.dart';
import 'ui/edge_dock.dart';
import 'ui/theme.dart';

const _windowSize = Size(420, 720);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  final options = WindowOptions(
    size: _windowSize,
    minimumSize: Size(360, 480),
    titleBarStyle: TitleBarStyle.hidden,
    windowButtonVisibility: false,
    skipTaskbar: true,
    alwaysOnTop: true,
    // Windows'ta cam (bulanıklık) yok: saydam pencere arkayı çıplak gösterir
    // ve yeniden çizimde beyaz yanıp söner. Orada düz koyu zemin.
    backgroundColor:
        Platform.isWindows ? AppColors.background : Colors.transparent,
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.setAsFrameless();
    await EdgeDock.instance.start();
  });

  await _setUpTray();
  final state = await AppState.create();
  runApp(AppSignal(state: state));
  Updater.start();
}

/// Menü çubuğu (Mac) ya da saat yanı (Windows) simgesi. Tıklayınca pencere
/// açılır/kapanır; sağ tık menüsünden çıkılır.
Future<void> _setUpTray() async {
  await trayManager.setIcon(
    Platform.isWindows ? 'assets/tray_icon.ico' : 'assets/tray_icon.png',
    isTemplate: true,
  );
  await trayManager.setToolTip('App Signal');
  await trayManager.setContextMenu(
    Menu(
      items: [
        MenuItem(key: 'toggle', label: 'Göster / Gizle'),
        MenuItem(key: 'refresh', label: 'Yenile'),
        MenuItem(key: 'update', label: 'Güncellemeleri denetle'),
        MenuItem.separator(),
        MenuItem(key: 'quit', label: 'Çık'),
      ],
    ),
  );
}

class AppSignal extends StatefulWidget {
  const AppSignal({super.key, required this.state});

  final AppState state;

  @override
  State<AppSignal> createState() => _AppSignalState();
}

class _AppSignalState extends State<AppSignal> with TrayListener {
  @override
  void initState() {
    super.initState();
    trayManager.addListener(this);
    widget.state.addListener(_updateTitle);
  }

  @override
  void dispose() {
    widget.state.removeListener(_updateTitle);
    trayManager.removeListener(this);
    super.dispose();
  }

  String? _title;

  /// Menü çubuğunda simgenin yanında canlı kullanıcı (son 30 dk). Düşüş ya da
  /// kötü yorum varsa yanına uyarı işareti. Windows tepsisi başlık göstermez;
  /// aynı bilgi simgenin ipucuna yazılır.
  void _updateTitle() {
    final s = widget.state;
    final live = s.ga4Data?.realtime;
    final alert = s.drops.isNotEmpty || s.lowReviews.isNotEmpty;
    final title = [if (live != null) '$live', if (alert) '⚠'].join(' ');
    if (title == _title) return;
    _title = title;
    if (Platform.isMacOS) {
      trayManager.setTitle(title);
    } else {
      trayManager.setToolTip(
        [
          'App Signal',
          if (live != null) '$live canlı',
          if (alert) '⚠',
        ].join(' · '),
      );
    }
  }

  Future<void> _toggleWindow() => EdgeDock.instance.toggle();

  @override
  void onTrayIconMouseDown() => _toggleWindow();

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'toggle':
        _toggleWindow();
      case 'refresh':
        widget.state.refresh(force: true);
      case 'update':
        Updater.checkNow();
      case 'quit':
        trayManager.destroy();
        exit(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'App Signal',
      navigatorKey: EdgeDock.instance.navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: Dashboard(state: widget.state),
    );
  }
}
