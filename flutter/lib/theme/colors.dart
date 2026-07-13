import 'package:flutter/material.dart';

const appBrandColor = Color(0xFF007AFF);
const appDarkBrandColor = Color(0xFF0A84FF);

// Eight-level neutral palette. Lower levels carry stronger foreground
// emphasis; higher levels are progressively larger background surfaces.
const appLightLevel1 = Color(0xFF15141A);
const appLightLevel2 = Color(0xFF2B2B33);
const appLightLevel3 = Color(0xFF5A5A66);
const appLightLevel4 = Color(0xFF8D8D99);
const appLightLevel5 = Color(0xFFC4C4CC);
const appLightLevel6 = Color(0xFFE1E1E5);
const appLightLevel7 = Color(0xFFF2F2F2);
const appLightLevel8 = Color(0xFFFFFFFF);

const appDarkLevel1 = Color(0xFFFAFAFF);
const appDarkLevel2 = Color(0xFFFAFAFF);
const appDarkLevel3 = Color(0xFFBCBBBF);
const appDarkLevel4 = Color(0xFF8A898C);
const appDarkLevel5 = Color(0xFF585759);
const appDarkLevel6 = Color(0xFF3F3E40);
const appDarkLevel7 = Color(0xFF323233);
const appDarkLevel8 = Color(0xFF1A191A);

// Compatibility aliases used by existing page-specific helpers.
const appPanelBorderColor = appLightLevel5;
const appWorkspaceBackground = appLightLevel7;
const appDarkAppBackground = appDarkLevel8;
const appDarkWorkspaceBackground = appDarkLevel8;
const appDarkPanelBackground = appDarkLevel7;
const appDarkControlBackground = appDarkLevel6;
const appDarkCanvasBackground = appDarkLevel8;
const appDarkBorderColor = appDarkLevel5;
const appDarkTextColor = appDarkLevel1;
const appMutedLightTextColor = appLightLevel2;

@immutable
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  const AppSemanticColors({
    required this.textPrimary,
    required this.textBody,
    required this.textSecondary,
    required this.textPlaceholder,
    required this.borderDisabled,
    required this.surfaceRaised,
    required this.surface,
    required this.page,
  });

  static const light = AppSemanticColors(
    textPrimary: appLightLevel1,
    textBody: appLightLevel2,
    textSecondary: appLightLevel3,
    textPlaceholder: appLightLevel4,
    borderDisabled: appLightLevel5,
    surfaceRaised: appLightLevel6,
    surface: appLightLevel8,
    page: appLightLevel7,
  );

  static const dark = AppSemanticColors(
    textPrimary: appDarkLevel1,
    textBody: appDarkLevel2,
    textSecondary: appDarkLevel3,
    textPlaceholder: appDarkLevel4,
    borderDisabled: appDarkLevel5,
    surfaceRaised: appDarkLevel6,
    surface: appDarkLevel7,
    page: appDarkLevel8,
  );

  final Color textPrimary;
  final Color textBody;
  final Color textSecondary;
  final Color textPlaceholder;
  final Color borderDisabled;
  final Color surfaceRaised;
  final Color surface;
  final Color page;

  @override
  AppSemanticColors copyWith({
    Color? textPrimary,
    Color? textBody,
    Color? textSecondary,
    Color? textPlaceholder,
    Color? borderDisabled,
    Color? surfaceRaised,
    Color? surface,
    Color? page,
  }) {
    return AppSemanticColors(
      textPrimary: textPrimary ?? this.textPrimary,
      textBody: textBody ?? this.textBody,
      textSecondary: textSecondary ?? this.textSecondary,
      textPlaceholder: textPlaceholder ?? this.textPlaceholder,
      borderDisabled: borderDisabled ?? this.borderDisabled,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      surface: surface ?? this.surface,
      page: page ?? this.page,
    );
  }

  @override
  AppSemanticColors lerp(covariant AppSemanticColors? other, double t) {
    if (other == null) return this;
    return AppSemanticColors(
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textBody: Color.lerp(textBody, other.textBody, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textPlaceholder: Color.lerp(textPlaceholder, other.textPlaceholder, t)!,
      borderDisabled: Color.lerp(borderDisabled, other.borderDisabled, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      page: Color.lerp(page, other.page, t)!,
    );
  }
}

const labelColorPalette = [
  Color(0xFF2563EB),
  Color(0xFFDC2626),
  Color(0xFF16A34A),
  Color(0xFF9333EA),
  Color(0xFFEA580C),
  Color(0xFF0891B2),
  Color(0xFFDB2777),
  Color(0xFF4F46E5),
  Color(0xFF65A30D),
  Color(0xFFB45309),
];
