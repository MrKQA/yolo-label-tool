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
