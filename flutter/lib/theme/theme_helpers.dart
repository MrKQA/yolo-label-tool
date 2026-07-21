// =============================================================================
// theme_helpers.dart - Theme Helper Functions / 主题辅助函数
// =============================================================================
// Convenience functions: isDarkMode, panelColor, controlColor, canvasColor,
// workspaceColor, borderColor, and primaryTextColor — each reads the current
// theme brightness to return the correct color token.
//
// 便捷函数：isDarkMode、panelColor、controlColor 等，根据当前主题亮度返回正确的颜色。
// =============================================================================

import 'package:flutter/material.dart';

import 'colors.dart';

const appFontFamily = 'MiSans';
const appFontFamilyFallback = <String>[
  'Microsoft YaHei',
  'Microsoft YaHei UI',
  'Segoe UI',
];

bool isDarkMode(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark;

AppSemanticColors semanticColors(BuildContext context) =>
    Theme.of(context).extension<AppSemanticColors>() ??
    (isDarkMode(context) ? AppSemanticColors.dark : AppSemanticColors.light);

Color panelColor(BuildContext context) => appPanelColor(isDarkMode(context));

Color controlColor(BuildContext context) =>
    appControlColor(isDarkMode(context));

Color canvasColor(BuildContext context) => appCanvasColor(isDarkMode(context));

Color workspaceColor(BuildContext context) =>
    appWorkspaceColor(isDarkMode(context));

Color borderColor(BuildContext context) => appBorderColor(isDarkMode(context));

Color primaryTextColor(BuildContext context) =>
    semanticColors(context).textPrimary;

Color bodyTextColor(BuildContext context) => semanticColors(context).textBody;

Color secondaryTextColor(BuildContext context) =>
    semanticColors(context).textSecondary;

Color placeholderTextColor(BuildContext context) =>
    semanticColors(context).textPlaceholder;

Color disabledTextColor(BuildContext context) =>
    semanticColors(context).borderDisabled;

Color appPanelColor(bool dark) => dark ? appDarkLevel7 : appLightLevel8;

Color appControlColor(bool dark) => dark ? appDarkLevel6 : appLightLevel8;

Color appCanvasColor(bool dark) => dark ? appDarkLevel8 : appLightLevel8;

Color appWorkspaceColor(bool dark) => dark ? appDarkLevel8 : appLightLevel7;

Color appTextColor(bool dark) => dark ? appDarkLevel2 : appLightLevel2;

Color appBorderColor(bool dark) => dark ? appDarkLevel5 : appLightLevel5;
