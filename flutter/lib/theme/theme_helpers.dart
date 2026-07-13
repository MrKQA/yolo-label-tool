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

const appFontFamily = 'Microsoft YaHei';

bool isDarkMode(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark;

Color panelColor(BuildContext context) => appPanelColor(isDarkMode(context));

Color controlColor(BuildContext context) =>
    appControlColor(isDarkMode(context));

Color canvasColor(BuildContext context) => appCanvasColor(isDarkMode(context));

Color workspaceColor(BuildContext context) =>
    appWorkspaceColor(isDarkMode(context));

Color borderColor(BuildContext context) => appBorderColor(isDarkMode(context));

Color primaryTextColor(BuildContext context) =>
    appTextColor(isDarkMode(context));

Color appPanelColor(bool dark) => dark ? appDarkPanelBackground : Colors.white;

Color appControlColor(bool dark) =>
    dark ? appDarkControlBackground : Colors.white;

Color appCanvasColor(bool dark) =>
    dark ? appDarkCanvasBackground : Colors.white;

Color appWorkspaceColor(bool dark) =>
    dark ? appDarkWorkspaceBackground : appWorkspaceBackground;

Color appTextColor(bool dark) =>
    dark ? appDarkTextColor : appMutedLightTextColor;

Color appBorderColor(bool dark) =>
    dark ? appDarkBorderColor : appPanelBorderColor;
