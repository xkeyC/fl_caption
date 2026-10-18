import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../main.dart' show quitApp;
import 'captions.dart';
import 'i18n.dart';
import 'window_mode.dart';
import 'windows.dart';

/// The tray icon: the way back to a locked (click-through) caption bar.
/// Linux panels report no icon clicks, so everything is in the menu too.
class AppTray {
  AppTray._(this._container, this._icon);

  final ProviderContainer _container;
  final TrayIcon _icon;
  static AppTray? _instance;

  static Future<void> install(ProviderContainer container) async {
    final icon = TrayIcon.create();
    if (icon == null) return;
    final tray = AppTray._(container, icon);
    _instance = tray;
    icon.icon = ImageAsset.fromAsset('assets/icons/app.png');
    icon.setTooltip('FL Caption');
    icon.setContextMenuTrigger(ContextMenuTrigger.rightClicked);
    icon.addListener((event) {
      if (event is TrayIconClickedEvent) tray._showBar();
    });
    tray.refresh();
    icon.setVisible(true);
    container.listen(captionProvider.select((s) => s.active), (_, _) => tray.refresh());
    container.listen(overlayProvider, (_, _) => tray.refresh());
  }

  static Future<void> remove() async {
    _instance?._icon.dispose();
    _instance = null;
  }

  void refresh() {
    final active = _container.read(captionProvider).active;
    final overlay = _container.read(overlayProvider.notifier);
    final menu = Menu.create();
    if (menu == null) return;
    void add(String label, Future<void> Function() onClick) {
      final item = MenuItem.createWithLabelAndType(label, MenuItemType.normal);
      if (item == null) return;
      item.addListener((event) async {
        if (event is MenuItemClickedEvent) {
          await onClick();
          refresh();
        }
      });
      menu.addItem(item);
    }

    add(
      active ? tr('停止字幕', 'Stop captions') : tr('开始字幕', 'Start captions'),
      () => _container.read(captionProvider.notifier).toggle(),
    );
    add(tr('设置', 'Settings'), () => openSettingsWindow());
    if (overlay.clickThrough) add(tr('解锁字幕条', 'Unlock the caption bar'), () => overlay.setClickThrough(false));
    menu.addSeparator();
    add(tr('退出', 'Quit'), () => quitApp(_container.read(captionProvider.notifier)));
    _icon.setContextMenu(menu);
  }

  Future<void> _showBar() async {
    final overlay = _container.read(overlayProvider.notifier);
    if (overlay.clickThrough) await overlay.setClickThrough(false);
    await windowManager.show();
    refresh();
  }
}
