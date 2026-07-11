import 'package:flutter/material.dart';

import 'models/app_status.dart';
import 'services/app_runtime.dart';
import 'services/i18n.dart';
import 'src/rust/api.dart';
import 'theme/colors.dart';
import 'theme/theme_helpers.dart';
import 'widgets/common/workspace_shell.dart';

class YoloLabelApp extends StatelessWidget {
  const YoloLabelApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguageStrings>(
      valueListenable: languageStringsNotifier,
      builder: (context, language, _) {
        return ValueListenableBuilder<ThemeMode>(
          valueListenable: themeModeNotifier,
          builder: (context, themeMode, _) {
            return MaterialApp(
              debugShowCheckedModeBanner: false,
              title: t('app.title'),
              themeMode: themeMode,
              theme: ThemeData(
                colorScheme: ColorScheme.fromSeed(seedColor: appBrandColor),
                fontFamily: appFontFamily,
                scaffoldBackgroundColor: appWorkspaceBackground,
                useMaterial3: true,
              ),
              darkTheme: ThemeData(
                colorScheme: ColorScheme.fromSeed(
                  seedColor: appDarkBrandColor,
                  brightness: Brightness.dark,
                ),
                brightness: Brightness.dark,
                fontFamily: appFontFamily,
                scaffoldBackgroundColor: appDarkAppBackground,
                dialogTheme: const DialogThemeData(
                  backgroundColor: appDarkPanelBackground,
                  titleTextStyle: TextStyle(
                    color: appDarkTextColor,
                    fontFamily: appFontFamily,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                dividerTheme: const DividerThemeData(color: appDarkBorderColor),
                menuTheme: const MenuThemeData(
                  style: MenuStyle(
                    backgroundColor: WidgetStatePropertyAll(
                      appDarkPanelBackground,
                    ),
                    surfaceTintColor: WidgetStatePropertyAll(
                      Colors.transparent,
                    ),
                  ),
                ),
                outlinedButtonTheme: OutlinedButtonThemeData(
                  style: OutlinedButton.styleFrom(
                    backgroundColor: appDarkControlBackground,
                    foregroundColor: appDarkTextColor,
                    side: const BorderSide(color: appDarkBorderColor),
                  ),
                ),
                textButtonTheme: TextButtonThemeData(
                  style: TextButton.styleFrom(
                    foregroundColor: appDarkBrandColor,
                  ),
                ),
                useMaterial3: true,
              ),
              home: const HomePage(),
            );
          },
        );
      },
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final Future<BridgeStatus> _status = _loadStatus();

  Future<BridgeStatus> _loadStatus() async {
    final greeting = await rustGreeting(name: 'Flutter');
    final modes = await supportedAnnotationModes();
    return BridgeStatus(greeting: greeting, modes: modes);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<BridgeStatus>(
        future: _status,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: SelectableText(
                  '${t('app.bridgeError')}:\n${snapshot.error}',
                ),
              ),
            );
          }

          return WorkspaceShell(status: snapshot.data!);
        },
      ),
    );
  }
}
