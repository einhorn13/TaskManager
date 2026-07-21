import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart' as acrylic;
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

/// Owns the Windows window lifecycle. On other platforms every operation is a
/// harmless no-op, so the rest of the UI does not need platform branches.
class AppWindowController with WindowListener, TrayListener {
  AppWindowController._();

  static final instance = AppWindowController._();

  final compactMode = ValueNotifier<bool>(false);
  bool _initialized = false;
  bool _quitting = false;
  Size? _regularSize;
  Offset? _regularPosition;
  String _languageCode = 'en';
  bool _acrylicReady = false;

  bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  Future<void> initialize() async {
    if (!isSupported || _initialized) return;
    _initialized = true;
    await windowManager.ensureInitialized();
    try {
      await acrylic.Window.initialize();
      _acrylicReady = true;
    } catch (_) {
      // Acrylic is decorative. Unsupported Windows configurations must not
      // prevent the task database or the rest of the UI from starting.
    }
    windowManager.addListener(this);
    trayManager.addListener(this);

    const options = WindowOptions(
      size: Size(1280, 720),
      minimumSize: Size(840, 600),
      center: true,
      title: 'Tasks',
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.setPreventClose(true);
      await windowManager.show();
      await windowManager.focus();
    });

    await trayManager.setIcon('windows/runner/resources/app_icon.ico');
    await trayManager.setToolTip('Tasks');
    await _updateTrayMenu();
  }

  Future<void> updateLocale(String languageCode) async {
    if (!isSupported || !_initialized || _languageCode == languageCode) return;
    _languageCode = languageCode;
    await _updateTrayMenu();
  }

  Future<void> _updateTrayMenu() async {
    final ru = _languageCode == 'ru';
    await trayManager.setContextMenu(Menu(items: [
      MenuItem(key: 'show', label: ru ? 'Открыть задачи' : 'Open tasks'),
      MenuItem(key: 'compact', label: ru ? 'Компактный вид' : 'Compact view'),
      MenuItem(key: 'hide', label: ru ? 'Свернуть в трей' : 'Hide to tray'),
      MenuItem.separator(),
      MenuItem(key: 'quit', label: ru ? 'Выйти' : 'Quit'),
    ]));
  }

  Future<void> enterCompactMode() async {
    if (!isSupported || !_initialized || compactMode.value) return;
    if (await windowManager.isMaximized()) await windowManager.unmaximize();
    _regularSize = await windowManager.getSize();
    _regularPosition = await windowManager.getPosition();
    compactMode.value = true;
    await windowManager.setBackgroundColor(Colors.transparent);
    await windowManager.setTitleBarStyle(
      TitleBarStyle.hidden,
      windowButtonVisibility: false,
    );
    await windowManager.setMinimumSize(const Size(360, 480));
    await windowManager.setSize(const Size(400, 620), animate: true);
    await windowManager.setAlwaysOnTop(true);
    if (_acrylicReady) {
      final dark =
          WidgetsBinding.instance.platformDispatcher.platformBrightness ==
              Brightness.dark;
      try {
        await acrylic.Window.setEffect(
          effect: acrylic.WindowEffect.acrylic,
          color: dark ? const Color(0x9920272E) : const Color(0x99F2F5F8),
          dark: dark,
        );
      } catch (_) {
        _acrylicReady = false;
      }
    }
    await showWindow();
  }

  Future<void> exitCompactMode() async {
    if (!isSupported || !_initialized || !compactMode.value) return;
    compactMode.value = false;
    if (_acrylicReady) {
      try {
        await acrylic.Window.setEffect(effect: acrylic.WindowEffect.disabled);
      } catch (_) {
        _acrylicReady = false;
      }
    }
    await windowManager.setAlwaysOnTop(false);
    await windowManager.setTitleBarStyle(TitleBarStyle.normal);
    await windowManager.setMinimumSize(const Size(840, 600));
    await windowManager.setSize(_regularSize ?? const Size(1280, 720),
        animate: true);
    if (_regularPosition case final position?) {
      await windowManager.setPosition(position, animate: true);
    } else {
      await windowManager.center();
    }
    await showWindow();
  }

  Future<void> hideToTray() async {
    if (!isSupported || !_initialized) return;
    await windowManager.setSkipTaskbar(true);
    await windowManager.hide();
  }

  Future<void> showWindow() async {
    if (!isSupported || !_initialized) return;
    await windowManager.setSkipTaskbar(false);
    if (await windowManager.isMinimized()) await windowManager.restore();
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> startDragging() async {
    if (!isSupported || !_initialized) return;
    await windowManager.startDragging();
  }

  Future<void> quit() async {
    if (!isSupported || !_initialized || _quitting) return;
    _quitting = true;
    await windowManager.setPreventClose(false);
    await trayManager.destroy();
    await windowManager.destroy();
  }

  @override
  void onWindowClose() {
    if (!_quitting) quit();
  }

  @override
  void onWindowMinimize() => hideToTray();

  @override
  void onTrayIconMouseDown() => showWindow();

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        showWindow();
        return;
      case 'compact':
        enterCompactMode();
        return;
      case 'hide':
        hideToTray();
        return;
      case 'quit':
        quit();
        return;
    }
  }
}
