import 'package:flutter/material.dart';

import 'colors.dart';

const appFontFamily = 'Microsoft YaHei';

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
