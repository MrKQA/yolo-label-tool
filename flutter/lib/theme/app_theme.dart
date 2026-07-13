import 'dart:ui';

import 'package:flutter/material.dart';

import 'colors.dart';
import 'theme_helpers.dart';

const appMotionFast = Duration(milliseconds: 150);
const appMotionStandard = Duration(milliseconds: 200);
const appMotionEmphasized = Duration(milliseconds: 300);
const appMotionCurve = Curves.easeOutCubic;

ThemeData buildAppTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final palette = dark ? AppSemanticColors.dark : AppSemanticColors.light;
  final primary = dark ? appDarkBrandColor : appBrandColor;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: primary,
    onPrimary: Colors.white,
    primaryContainer: dark ? const Color(0xFF123E67) : const Color(0xFFDCEBFF),
    onPrimaryContainer: dark
        ? const Color(0xFFDCEAFF)
        : const Color(0xFF12325C),
    secondary: dark ? const Color(0xFF38BDF8) : const Color(0xFF087EA4),
    onSecondary: dark ? appDarkLevel8 : Colors.white,
    secondaryContainer: dark
        ? const Color(0xFF153B4B)
        : const Color(0xFFDDF4FC),
    onSecondaryContainer: dark
        ? const Color(0xFFD8F4FF)
        : const Color(0xFF123743),
    error: dark ? const Color(0xFFFF6B6B) : const Color(0xFFB42318),
    onError: Colors.white,
    errorContainer: dark ? const Color(0xFF5A2528) : const Color(0xFFFFE4E2),
    onErrorContainer: dark ? const Color(0xFFFFE4E2) : const Color(0xFF651A16),
    surface: palette.page,
    surfaceDim: dark ? appDarkLevel8 : appLightLevel7,
    surfaceBright: dark ? appDarkLevel6 : appLightLevel8,
    surfaceContainerLowest: palette.page,
    surfaceContainerLow: palette.surface,
    surfaceContainer: palette.surface,
    surfaceContainerHigh: palette.surfaceRaised,
    surfaceContainerHighest: palette.surfaceRaised,
    onSurface: palette.textBody,
    onSurfaceVariant: palette.textSecondary,
    outline: palette.borderDisabled,
    outlineVariant: palette.surfaceRaised,
    shadow: Colors.black,
    scrim: Colors.black,
    inverseSurface: dark ? appLightLevel8 : appDarkLevel8,
    onInverseSurface: dark ? appLightLevel2 : appDarkLevel2,
    inversePrimary: dark ? appBrandColor : appDarkBrandColor,
    surfaceTint: Colors.transparent,
  );
  final base = ThemeData(
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: appFontFamily,
    fontFamilyFallback: appFontFamilyFallback,
    scaffoldBackgroundColor: palette.page,
    canvasColor: palette.page,
    cardColor: palette.surface,
    disabledColor: palette.borderDisabled,
    useMaterial3: true,
    visualDensity: const VisualDensity(horizontal: -0.25, vertical: -0.25),
    extensions: [palette],
  );
  final textTheme = _buildTextTheme(base.textTheme, palette);
  final controlShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(8),
  );
  final enabledBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(8),
    borderSide: BorderSide(
      color: palette.borderDisabled.withValues(alpha: dark ? 0.55 : 0.62),
    ),
  );

  return base.copyWith(
    textTheme: textTheme,
    primaryTextTheme: textTheme,
    dividerColor: palette.borderDisabled,
    dividerTheme: DividerThemeData(
      color: palette.borderDisabled,
      thickness: 1,
      space: 1,
    ),
    iconTheme: IconThemeData(color: palette.textSecondary, size: 20),
    cardTheme: CardThemeData(
      color: palette.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: palette.borderDisabled.withValues(alpha: dark ? 0.38 : 0.46),
        ),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: palette.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: dark ? 0.34 : 0.12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      titleTextStyle: textTheme.titleLarge,
      contentTextStyle: textTheme.bodyMedium,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: palette.surface,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      hintStyle: textTheme.bodyMedium?.copyWith(color: palette.textPlaceholder),
      labelStyle: textTheme.bodyMedium?.copyWith(color: palette.textSecondary),
      floatingLabelStyle: textTheme.bodySmall?.copyWith(color: primary),
      enabledBorder: enabledBorder,
      border: enabledBorder,
      focusedBorder: enabledBorder.copyWith(
        borderSide: BorderSide(color: primary, width: 1.4),
      ),
      disabledBorder: enabledBorder.copyWith(
        borderSide: BorderSide(color: palette.surfaceRaised),
      ),
      errorBorder: enabledBorder.copyWith(
        borderSide: BorderSide(color: scheme.error),
      ),
      focusedErrorBorder: enabledBorder.copyWith(
        borderSide: BorderSide(color: scheme.error, width: 1.4),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(40, 40),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: controlShape,
        textStyle: textTheme.labelLarge,
        animationDuration: appMotionStandard,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(40, 40),
        foregroundColor: palette.textBody,
        backgroundColor: palette.surface,
        disabledForegroundColor: palette.borderDisabled,
        side: BorderSide(
          color: palette.borderDisabled.withValues(alpha: dark ? 0.60 : 0.72),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        shape: controlShape,
        textStyle: textTheme.labelLarge,
        animationDuration: appMotionStandard,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(36, 36),
        foregroundColor: primary,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: controlShape,
        textStyle: textTheme.labelLarge,
        animationDuration: appMotionStandard,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(36, 36)),
        iconSize: const WidgetStatePropertyAll(20),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? palette.borderDisabled
              : palette.textSecondary,
        ),
        overlayColor: WidgetStatePropertyAll(
          primary.withValues(alpha: dark ? 0.18 : 0.10),
        ),
        shape: WidgetStatePropertyAll(controlShape),
        animationDuration: appMotionStandard,
      ),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(palette.surface),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(6),
        shadowColor: WidgetStatePropertyAll(
          Colors.black.withValues(alpha: dark ? 0.30 : 0.10),
        ),
        shape: WidgetStatePropertyAll(controlShape),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(vertical: 4),
        ),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: palette.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 6,
      shape: controlShape,
      textStyle: textTheme.bodyMedium,
    ),
    listTileTheme: ListTileThemeData(
      dense: true,
      minTileHeight: 40,
      iconColor: palette.textSecondary,
      textColor: palette.textBody,
      shape: controlShape,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: dark ? appLightLevel2 : appDarkLevel7,
        borderRadius: BorderRadius.circular(4),
      ),
      textStyle: TextStyle(
        color: dark ? appLightLevel8 : appDarkLevel1,
        fontFamily: appFontFamily,
        fontFamilyFallback: appFontFamilyFallback,
        fontSize: 12,
        letterSpacing: 0,
      ),
      waitDuration: const Duration(milliseconds: 450),
    ),
    sliderTheme: base.sliderTheme.copyWith(
      activeTrackColor: primary,
      inactiveTrackColor: palette.surfaceRaised,
      thumbColor: primary,
      overlayColor: primary.withValues(alpha: 0.12),
      trackHeight: 3,
    ),
    scrollbarTheme: ScrollbarThemeData(
      interactive: true,
      thickness: const WidgetStatePropertyAll(8),
      radius: const Radius.circular(4),
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.hovered)
            ? palette.textPlaceholder
            : palette.borderDisabled,
      ),
      trackColor: WidgetStatePropertyAll(
        palette.surfaceRaised.withValues(alpha: 0.48),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: primary,
      linearTrackColor: palette.surfaceRaised,
      circularTrackColor: palette.surfaceRaised,
    ),
    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
      side: BorderSide(color: palette.textPlaceholder),
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? primary : null,
      ),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? primary
            : palette.textPlaceholder,
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? Colors.white
            : palette.textPlaceholder,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? primary
            : palette.surfaceRaised,
      ),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: FadeUpwardsPageTransitionsBuilder(),
        TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
        TargetPlatform.macOS: FadeUpwardsPageTransitionsBuilder(),
        TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
      },
    ),
    splashColor: primary.withValues(alpha: dark ? 0.16 : 0.10),
    highlightColor: primary.withValues(alpha: dark ? 0.10 : 0.06),
    hoverColor: primary.withValues(alpha: dark ? 0.12 : 0.07),
    focusColor: primary.withValues(alpha: dark ? 0.18 : 0.10),
  );
}

TextTheme _buildTextTheme(TextTheme base, AppSemanticColors palette) {
  TextStyle style(
    double size,
    FontWeight weight,
    Color color, {
    double height = 1.35,
  }) {
    return TextStyle(
      fontFamily: appFontFamily,
      fontFamilyFallback: appFontFamilyFallback,
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
      letterSpacing: 0,
    );
  }

  return base.copyWith(
    displayLarge: style(28, FontWeight.w600, palette.textPrimary),
    displayMedium: style(24, FontWeight.w600, palette.textPrimary),
    displaySmall: style(21, FontWeight.w600, palette.textPrimary),
    headlineLarge: style(22, FontWeight.w600, palette.textPrimary),
    headlineMedium: style(19, FontWeight.w600, palette.textPrimary),
    headlineSmall: style(17, FontWeight.w600, palette.textPrimary),
    titleLarge: style(17, FontWeight.w600, palette.textPrimary),
    titleMedium: style(15, FontWeight.w600, palette.textPrimary),
    titleSmall: style(13, FontWeight.w600, palette.textPrimary),
    bodyLarge: style(15, FontWeight.w400, palette.textBody),
    bodyMedium: style(13, FontWeight.w400, palette.textBody),
    bodySmall: style(12, FontWeight.w400, palette.textSecondary),
    labelLarge: style(13, FontWeight.w600, palette.textBody, height: 1.2),
    labelMedium: style(12, FontWeight.w500, palette.textSecondary, height: 1.2),
    labelSmall: style(11, FontWeight.w500, palette.textSecondary, height: 1.2),
  );
}

class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.stylus,
    PointerDeviceKind.trackpad,
  };

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const ClampingScrollPhysics();
  }
}
