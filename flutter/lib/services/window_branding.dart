import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/config.dart';
import 'app_runtime.dart';
import 'logger.dart';

const _windowBrandingChannel = MethodChannel('yolo_label_tool/window_branding');

@immutable
class WindowBranding {
  const WindowBranding({
    this.displayName = defaultApplicationDisplayName,
    this.iconPath = '',
  });

  final String displayName;
  final String iconPath;
}

final ValueNotifier<WindowBranding> windowBrandingNotifier =
    ValueNotifier<WindowBranding>(const WindowBranding());

Future<void> applyWindowBranding(AppSettings settings) async {
  final branding = WindowBranding(
    displayName: settings.effectiveApplicationDisplayName,
    iconPath: settings.applicationIconPath.trim(),
  );
  windowBrandingNotifier.value = branding;
  if (!Platform.isWindows) {
    return;
  }

  try {
    await _windowBrandingChannel.invokeMethod<void>('update', {
      'displayName': branding.displayName,
      'iconPath': branding.iconPath,
    });
  } on Object catch (error) {
    logApp(
      'SETTINGS',
      'Window branding update failed: $error',
      level: AppLogLevel.warning,
    );
  }
}
